//
//  SBAArchiveManager.swift
//  BridgeApp
//
//  Copyright © 2018 Sage Bionetworks. All rights reserved.
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

open class SBAArchiveManager : NSObject, RSDDataArchiveManager {
    
    /// Pointer to the shared configuration to use.
    public var configuration: SBABridgeConfiguration {
        return SBABridgeConfiguration.shared
    }
    
    /// Pointer to the default factory to use for serialization.
    open var factory: RSDFactory {
        return SBAFactory.shared
    }
    
    /// Get the schema info associated with the given activity identifier. By default, this looks at the
    /// shared bridge configuration's schema reference map.
    open func schemaInfo(for activityIdentifier: String) -> RSDSchemaInfo? {
        return self.configuration.schemaInfo(for: activityIdentifier)
    }
    
    /// A serial queue used to manage data crunching.
    public let offMainQueue = DispatchQueue(label: "org.sagebionetworks.BridgeApp.SBAArchiveManager")
    
    /// Archive and upload the results from the task view model.
    public final func archiveAndUpload(_ taskState: RSDTaskState, completion: ((_ error: Error?) -> Void)? = nil) {
        offMainQueue.async {
            self._archiveAndUpload(taskState, completion: completion)
        }
    }
    
    /// DO NOT MAKE OPEN. This method retains the task path until archiving is completed and because it
    /// nils out the pointer to the task path with a strong reference to `self`, it will also retain the
    /// archive manager until the completion block is called. syoung 05/31/2018
    private final func _archiveAndUpload(_ taskState: RSDTaskState, completion: ((_ error: Error?) -> Void)? = nil) {
        let uuid = UUID()
        self._retainedPaths[uuid] = taskState
        taskState.archiveResults(with: self) { (_ error: Error?) in
            self._retainedPaths[uuid] = nil
            completion?(error)
        }
    }
    private var _retainedPaths: [UUID : RSDTaskState] = [:]
    
    /// Base class implementation returns nil.
    open func scheduledActivity(for taskResult: RSDTaskResult, scheduleIdentifier: String?) -> SBBScheduledActivity? {
        return nil
    }
    
    /// Should the task result archiving be continued if there was an error adding data to the current
    /// archive? Default behavior is to flush the archive and then return `false`.
    ///
    /// - parameters:
    ///     - archive: The current archive being built.
    ///     - error: The encoding error that was thrown.
    /// - returns: Whether or not archiving should continue. Default = `false`.
    open func shouldContinueOnFail(for archive: RSDDataArchive, error: Error) -> Bool {
        debugPrint("ERROR! Failed to archive results: \(error)")
        // Flush the archive.
        (archive as? SBBDataArchive)?.remove()
        return false
    }
    
    /// When archiving a task result, it is possible that the results of a task need to be split into
    /// multiple archives -- for example, when combining two or more activities within the same task. If the
    /// task result components should be added to the current archive, then the manager should return
    /// `currentArchive` as the response. If the task result *for this section* should be ignored, then the
    /// manager should return `nil`. This allows the application to only upload data that is needed by the
    /// study, and not include information that is ignored by *this* study, but may be of interest to other
    /// researchers using the same task protocol.
    open func dataArchiver(for taskResult: RSDTaskResult, scheduleIdentifier: String?, currentArchive: RSDDataArchive?) -> RSDDataArchive? {
        
        // Look for a schema info associated with this portion of the task result. If not found, then
        // return the current archive.
        let schema = (taskResult as? RSDTaskRunResult)?.schemaInfo ?? self.schemaInfo(for: taskResult.identifier)
        guard (currentArchive == nil) || (schema != nil) else {
            return currentArchive
        }
        
        let schemaInfo = schema ?? RSDSchemaInfoObject(identifier: taskResult.identifier, revision: 1)
        let archiveIdentifier = schemaInfo.schemaIdentifier ?? taskResult.identifier
        let schedule = self.scheduledActivity(for: taskResult, scheduleIdentifier: scheduleIdentifier)
            ?? (currentArchive as? SBAScheduledActivityArchive)?.schedule
        let isPlaceholder = (currentArchive == nil) && (schema == nil) && (schedule == nil)
        
        // If there is a top-level archive then return the exisiting if and only if the identifiers are the
        // same or the schema is nil.
        if let inputArchive = currentArchive,
            ((inputArchive.identifier == archiveIdentifier) || (schema == nil)) {
            return inputArchive
        }
        
        guard !isPlaceholder else {
            return SBAScheduledActivityArchive(identifier: archiveIdentifier, schemaInfo: schemaInfo, schedule: schedule, isPlaceholder: true)
        }
        
        // Otherwise, instantiate a new archive.
        let archive = self.instantiateArchive(archiveIdentifier, for: schedule, with: schemaInfo)
        (archive as? SBAScheduledActivityArchive)?.taskResult = taskResult
        return archive
    }
    
    /// Instantiate the data archive to use for this schedule and schema info.
    open func instantiateArchive(_ archiveIdentifier: String, for schedule:SBBScheduledActivity?, with schemaInfo: RSDSchemaInfo) -> RSDDataArchive {
        let archive = SBAScheduledActivityArchive(identifier: archiveIdentifier, schemaInfo: schemaInfo, schedule: schedule, isPlaceholder: false)
        archive.usesV1LegacySchema = self.usesV1LegacySchema(archiveIdentifier, for: schedule)
        return archive
    }
    
    /// Does this archive use V1 legacy formatting for archiving? By default, this will return `true`
    /// for archives that do not map to a survey if the AppConfig *also* marks the study as using
    /// V1 legacy formatting for schemas.
    open func usesV1LegacySchema(_ archiveIdentifier: String, for schedule:SBBScheduledActivity?) -> Bool {
        return (schedule?.activity.survey == nil) && self.configuration.usesV1LegacyArchiving
    }
    
    /// Finalize the upload of all the created archives.
    public final func encryptAndUpload(taskResult: RSDTaskResult, dataArchives: [RSDDataArchive], completion:@escaping (() -> Void)) {
        let archives: [SBBDataArchive] = dataArchives.compactMap {
            guard let archive = $0 as? SBBDataArchive, self.shouldUpload(archive: archive) else { return nil }
            return archive
        }
        #if DEBUG
        archives.forEach {
            guard let archive = $0 as? SBAScheduledActivityArchive else { return }
            self.copyTestArchive(archive: archive)
        }
        #endif
        SBBDataArchive.encryptAndUploadArchives(archives)
        completion()
    }
    
    /// This method is called during `encryptAndUpload()` to allow subclasses to cancel uploading an archive.
    ///
    /// - returns: Whether or not to upload. Default is to return `true` if the archive is not empty.
    open func shouldUpload(archive: SBBDataArchive) -> Bool {
        return !archive.isEmpty()
    }
    
    /// By default, if an archive fails, the error is printed and that's all that is done.
    open func handleArchiveFailure(taskResult: RSDTaskResult, error: Error, completion:@escaping (() -> Void)) {
        debugPrint("WARNING! Failed to archive \(taskResult.identifier). \(error)")
        completion()
    }
    
    #if DEBUG
    private func copyTestArchive(archive: SBAScheduledActivityArchive) {
        guard SBAParticipantManager.shared.isTestUser else { return }
        do {
            if !archive.isCompleted {
                try archive.complete()
            }
            let fileManager = FileManager.default
            
            let outputDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dirURL = outputDirectory.appendingPathComponent("archives", isDirectory: true)
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
            
            // Scrub non-alphanumeric characters from the identifer
            var characterSet = CharacterSet.alphanumerics
            characterSet.invert()
            var filename = archive.identifier
            while let range = filename.rangeOfCharacter(from: characterSet) {
                filename.removeSubrange(range)
            }
            filename.append("-")
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HHmm"
            let dateString = dateFormatter.string(from: Date())
            filename.append(dateString)
            let debugURL = dirURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("zip")
            try fileManager.copyItem(at: archive.unencryptedURL, to: debugURL)
            debugPrint("Copied archive to \(debugURL)")
            
        } catch let err {
            debugPrint("Failed to copy archive: \(err)")
        }
    }
    #endif
}
