//
//  SBAScheduledActivityArchive.swift
//  BridgeApp (iOS)
//
//  Copyright © 2016-2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation
import JsonModel

private let kScheduledActivityGuidKey         = "scheduledActivityGuid"
private let kScheduleIdentifierKey            = "scheduleIdentifier"
private let kScheduledOnKey                   = "scheduledOn"
private let kScheduledActivityLabelKey        = "activityLabel"
private let kDataGroups                       = "dataGroups"
private let kSchemaRevisionKey                = "schemaRevision"
private let kSurveyCreatedOnKey               = "surveyCreatedOn"
private let kSurveyGuidKey                    = "surveyGuid"

private let kMetadataFilename                 = "metadata.json"


/// A subclass of the `SBBDataArchive` that implements `RSDDataArchive` for task results.
open class SBAScheduledActivityArchive: SBBDataArchive, RSDDataArchive {
    
    /// The identifier for this archive.
    public let identifier: String
    
    /// The schedule used to start this task (if any).
    public let schedule: SBBScheduledActivity?
    
    /// The schema info for this archive.
    public let schemaInfo: RSDSchemaInfo
    
    /// Is the archive a top-level archive?
    public let isPlaceholder: Bool
    
    /// Hold the task result (if any) used to create the archive.
    internal var taskResult: RSDTaskResult?
    
    /// The schedule identifier is the `SBBScheduledActivity.guid` which is a combination of the activity
    /// guid and the `scheduledOn` property.
    public var scheduleIdentifier: String? {
        return schedule?.guid
    }
    
    public init(identifier: String, schemaInfo: RSDSchemaInfo, schedule: SBBScheduledActivity?, isPlaceholder: Bool = false) {
        self.identifier = identifier
        self.schedule = schedule
        self.schemaInfo = schemaInfo
        self.isPlaceholder = isPlaceholder
        super.init(reference: schemaInfo.schemaIdentifier ?? identifier, jsonValidationMapping: nil)
        
        // set info values.
        self.setArchiveInfoObject(NSNumber(value: schemaInfo.schemaVersion), forKey: kSchemaRevisionKey)
        if let surveyReference = schedule?.activity.survey {
            // Survey schema is better matched by created date and survey guid
            self.setArchiveInfoObject(surveyReference.guid, forKey: kSurveyGuidKey)
            let createdOn = surveyReference.createdOn ?? Date()
            if let stamp = (createdOn as NSDate).iso8601String() {
                self.setArchiveInfoObject(stamp, forKey: kSurveyCreatedOnKey)
            }
        }
    }
    
    /// syoung 07/21/2020 Change request to include all files by default.
    open func shouldInsertData(for filename: RSDReservedFilename) -> Bool {
        true
    }
    
    /// Get the archivable object for the given result.
    open func archivableData(for result: RSDResult, sectionIdentifier: String?, stepPath: String?) -> RSDArchivable? {
        if self.usesV1LegacySchema, let answerResult = result as? RSDAnswerResult {
            return SBAAnswerResultWrapper(sectionIdentifier: sectionIdentifier, result: answerResult)
        }
        else if let archivable = result as? RSDArchivable {
            return archivable
        }
        else {
            return nil
        }
    }
    
    /// Insert the data into the archive. By default, this will call `insertData(intoArchive:,filename:, createdOn:)`.
    ///
    /// - note: The "answers.json" file is special-cased to *not* include the `.json` extension if this is
    /// for a `v1_legacy` archive. This allows the v1 schema to use `answers.foo` which reads better in the
    /// Synapse tables.
    open func insertDataIntoArchive(_ data: Data, manifest: RSDFileManifest) throws {
        var filename = manifest.filename
        let fileKey = (filename as NSString).deletingPathExtension
        if let reserved = RSDReservedFilename(rawValue: fileKey), reserved == .answers {
            if self.usesV1LegacySchema {
                filename = fileKey
            }
            else {
                self.dataFilename = filename
            }
        }
        self.insertData(intoArchive: data, filename: filename, createdOn: manifest.timestamp)
    }
    
    /// Close the archive.
    open func completeArchive(with metadata: RSDTaskMetadata) throws {
        let metadataDictionary = try metadata.rsd_jsonEncodedDictionary()
        try completeArchive(createdOn: metadata.startDate, with: metadataDictionary)
    }
    
    /// Close the archive with optional metadata from a task result.
    open func completeArchive(createdOn: Date, with metadata: [String : Any]? = nil) throws {
        // If the archive is empty and this is a placeholder archive, then exit early without
        // adding the metadata.
        if self.isEmpty() && isPlaceholder { return }
        
        // Set up the activity metadata.
        var metadataDictionary: [String : Any] = metadata ?? [:]
        
        // Add metadata values from the schedule.
        if let schedule = self.schedule {
            metadataDictionary[kScheduledActivityGuidKey] = schedule.guid
            metadataDictionary[kScheduleIdentifierKey] = schedule.activity.guid
            metadataDictionary[kScheduledOnKey] = (schedule.scheduledOn as NSDate).iso8601String()
            metadataDictionary[kScheduledActivityLabelKey] = schedule.activity.label
        }
        
        // Add the current data groups.
        if let dataGroups = SBAParticipantManager.shared.studyParticipant?.dataGroups {
            metadataDictionary[kDataGroups] = dataGroups.joined(separator: ",")
        }
        
        // insert the dictionary.
        insertDictionary(intoArchive: metadataDictionary, filename: kMetadataFilename, createdOn: createdOn)
        
        // Look to see that the answers.json file is included, even if it is empty.
        // syoung 11/12/2019 This is a belt-and-suspenders for MP2-270 because I'm not sure why it
        // isn't always included and I can't repro the bug. Due to the timing of this issue with
        // needing to release, pushing a work-around while I continue to investigate.
        if !self.usesV1LegacySchema, self.answersDictionary == nil, let taskResult = self.taskResult {
            let builder = RSDDefaultScoreBuilder()
            let answers = builder.getScoringData(from: taskResult) as? [String : JsonSerializable] ?? [String : Any]()
            self.insertAnswersDictionary(answers)
        }
        
        // complete the archive.
        try complete()
    }
}

func bridgifyFilename(_ filename: String) -> String {
    return filename.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: " ", with: "_")
}

private let kIdentifierKey = "identifier"
private let kItemKey = "item"
private let kStartDateKey = "startDate"
private let kEndDateKey = "endDate"
private let kQuestionResultQuestionTypeKey = "questionType"
private let kQuestionResultSurveyAnswerKey = "answer"
private let kNumericResultUnitKey = "unit"

/// The wrapper is used to encode the surveys in the expected format.
struct SBAAnswerResultWrapper : RSDArchivable {
    
    let sectionIdentifier : String?
    let result : RSDAnswerResult

    var identifier: String {
        if let section = sectionIdentifier {
            return "\(section).\(result.identifier)"
        } else {
            return result.identifier
        }
    }
    
    func buildArchiveData(at stepPath: String?) throws -> (manifest: RSDFileManifest, data: Data)? {
        
        var json: [String : Any] = [:]

        // Synapse exporter expects item value to match base filename
        let item = bridgifyFilename(self.identifier)

        json[kIdentifierKey] = result.identifier
        json[kStartDateKey]  = result.startDate
        json[kEndDateKey]    = result.endDate
        json[kItemKey] = item
        if let answer = (result.value as? JsonValue)?.jsonObject() {
            json[result.answerType.bridgeAnswerKey] = answer
            json[kQuestionResultSurveyAnswerKey] = answer
            json[kQuestionResultQuestionTypeKey] = result.answerType.bridgeAnswerType
            if let unit = result.answerType.unit {
                json[kNumericResultUnitKey] = unit
            }
        }

        let jsonObject = (json as NSDictionary).jsonObject()
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
        let manifest = RSDFileManifest(filename: "\(item).json", timestamp: result.endDate, contentType: "application/json")
        return (manifest, data)
    }
}

extension RSDAnswerResultType {

    var bridgeAnswerType: String {
        guard self.sequenceType == nil else {
            return "MultipleChoice"
        }

        if let dataType = self.formDataType,
            case .collection(let collectionType, _) = dataType,
            collectionType == .singleChoice {
            return "SingleChoice"
        }

        switch self.baseType {
        case .boolean:
            return "Boolean"
        case .string, .data, .codable:
            return "Text"
        case .integer:
            return "Integer"
        case .decimal:
            return "Decimal"
        case .date:
            if self.dateFormat == "HH:mm:ss" || self.dateFormat == "HH:mm" {
                return "TimeOfDay"
            } else {
                return "Date"
            }
        }
    }

    var bridgeAnswerKey: String {
        guard self.sequenceType == nil else {
            return "choiceAnswers"
        }

        if let dataType = self.formDataType,
            case .collection(let collectionType, _) = dataType,
            collectionType == .singleChoice {
            return "choiceAnswers"
        }

        switch self.baseType {
        case .boolean:
            return "booleanAnswer"
        case .string, .data, .codable:
            return "textAnswer"
        case .integer, .decimal:
            return "numericAnswer"
        case .date:
            if self.dateFormat == "HH:mm:ss" || self.dateFormat == "HH:mm" {
                return "dateComponentsAnswer"
            } else {
                return "dateAnswer"
            }
        }

    }
}

