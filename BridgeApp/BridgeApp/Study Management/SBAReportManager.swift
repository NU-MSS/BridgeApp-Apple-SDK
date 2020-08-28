//
//  SBAReportManager.swift
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
import JsonModel

extension Notification.Name {
    
    /// Notification name posted by the `SBAReportManager` when the reports have been updated.
    public static let SBAUpdatedReports = Notification.Name(rawValue: "SBAUpdatedReports")
    
    /// Notification name posted by the `SBAReportManager` when a report will be saved to the server.
    public static let SBAWillSaveReports = Notification.Name(rawValue: "SBAWillSentReport")
}

/// The category for a given report. This is used to determine whether the `dateTime` or `localDate`
/// properties on `SBBReportData` are used to group the reports.
public enum SBAReportCategory : String, Codable {
    case singleton, groupByDay, timestamp
}

/// Convert the `SBBReportData` and `ReportQuery` into a single struct that can be sorted and filtered.
public struct SBAReport : Hashable {

    /// The identifier for the report.
    public let reportKey: RSDIdentifier

    /// The date for the report.
    public let date: Date
    
    /// The time zone of the report.
    public let timeZone: TimeZone
    
    /// The client data blob associated with this report.
    public let clientData: SBBJSONValue
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(reportKey)
        hasher.combine(date)
    }
    
    public static func == (lhs: SBAReport, rhs: SBAReport) -> Bool {
        return lhs.reportKey == rhs.reportKey && lhs.date == rhs.date
    }
    
    public init(reportKey: RSDIdentifier, date: Date, clientData: SBBJSONValue, timeZone: TimeZone = TimeZone.current) {
        self.reportKey = reportKey
        self.date = date
        self.clientData = clientData
        self.timeZone = timeZone
    }
    
    public init(identifier: String, date: Date?, json: JsonSerializable, timeZone: TimeZone = TimeZone.current) {
        self.reportKey = RSDIdentifier(rawValue: identifier)
        self.date = date ?? SBAReportSingletonDate
        self.clientData = json.toClientData()
        self.timeZone = timeZone
    }
    
    init(taskData: RSDTaskData) {
        self.init(identifier: taskData.identifier, date: taskData.timestampDate, json: taskData.json)
    }
}

extension SBAReport : RSDTaskData {
    
    public var identifier: String {
        return reportKey.stringValue
    }
    
    public var timestampDate: Date? {
        return (date == SBAReportSingletonDate) ? nil : date
    }
    
    public var json: JsonSerializable {
        return clientData.toJSONSerializable()
    }
    
    public var taskRunUUID: String? {
        return (self.clientData as? [String: Any])?[SBATaskRunUUIDKey] as? String
    }
}

/// The `localDate` used as the reference date for a singleton date object. The user's enrollment date is not
/// used for this so that the report can be found even if the enrollment date is changed.
public let SBAReportSingletonDate: Date = Date(timeIntervalSince1970: 0)

/// Key to use in a JSON dictionary for the task run UUID.
public let SBATaskRunUUIDKey: String = "taskRunUUID"

let kReportDateKey = "reportDate"
let kReportTimeZoneIdentifierKey = "timeZoneIdentifier"
let kReportClientDataKey = "clientData"

/// Default data source handler for reports. This manager is used to get and store `SBBReportData` objects.
open class SBAReportManager: SBAArchiveManager, RSDDataStorageManager {

    /// List of keys used in the notifications sent by this manager.
    public enum NotificationKey : String {
        case newReports
    }
    
    /// Pointer to the shared participant to use.
    public var participant: SBBStudyParticipant? {
        return SBAParticipantManager.shared.studyParticipant
    }
    
    /// Pointer to the shared participant manager.
    public var participantManager: SBBParticipantManagerProtocol {
        return BridgeSDK.participantManager
    }
    
    /// This is an internal function that can be used in testing instead of using `Date()` directly. It can
    /// then be overridden by a test subclass of this manager in order to return a known date.
    public func now() -> Date {
        return Date()
    }
    
    public override init() {
        super.init()
        
        NotificationCenter.default.addObserver(forName: .SBAWillSaveReports, object: nil, queue: .main) { (notification) in
            guard let newReports = notification.userInfo?[SBAReportManager.NotificationKey.newReports] as? [SBAReport]
                else {
                    return
            }
            self.addReports(with: newReports)
        }
        
        if shouldLoadOnInit {
            self.loadReports()
        }
    }
    
    /// Should the reports be loaded on initialization of the manager (default) or should the
    /// initial loading be handled *after* some set up or using lazy loading?
    open var shouldLoadOnInit: Bool {
        return true
    }
    
    /// Instantiate a new instance of a task view model from the given information. At least one of the input
    /// parameters should be non-nil or this with throw an exception.
    open func instantiateTaskViewModel(task: RSDTask?, taskInfo: RSDTaskInfo?) throws -> RSDTaskViewModel {
        if let task = task {
            let model = RSDTaskViewModel(task: task)
            model.dataManager = self
            return model
        }
        else if let taskInfo = taskInfo {
            let model = RSDTaskViewModel(taskInfo: taskInfo)
            model.dataManager = self
            return model
        }
        else {
            throw RSDValidationError.unexpectedNullObject("Either the task or task info must be non-nil")
        }
    }
    
    public var reports = Set<SBAReport>()
    
    /// The report query is used to describe the type of report being requested.
    public struct ReportQuery : Codable, Hashable {
        
        /// The identifier for the report.
        public let reportKey: RSDIdentifier
        
        /// The type of query.
        public let queryType: QueryType
        
        /// The type of report being requested.
        public enum QueryType : String, Codable {
            case mostRecent, all, today, dateRange
        }
        
        /// For `QueryType.dateRange`, the date range of the query.
        public var dateRange: (start: Date, end: Date)? {
            guard let start = self.startRange, let end = self.endRange else { return nil }
            return (start, end)
        }
        private let startRange: Date?
        private let endRange: Date?
        
        /// The report identifier as a string for use in requesting reports from Bridge.
        public var reportIdentifier: String {
            return reportKey.stringValue
        }
        
        public init(reportKey: RSDIdentifier, queryType: QueryType = .mostRecent, dateRange: (start: Date, end: Date)? = nil) {
            self.reportKey = reportKey
            self.queryType = queryType
            self.startRange = dateRange?.start
            self.endRange = dateRange?.end
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(reportKey)
            hasher.combine(queryType)
        }
    }
    
    /// A serial queue used to manage data crunching.
    static let offMainQueue = DispatchQueue(label: "org.sagebionetworks.BridgeApp.SBAReportManager.shared")
    
    /// The reports with which this manager is concerned. Default returns an empty array.
    open func reportQueries() -> [ReportQuery] {
        return []
    }
    
    /// Reload the data by fetching changes to the data that are used by this manager.
    open func reloadData() {
        loadReports()
    }
    
    /// State management for whether or not the manager is reloading.
    open var isReloading: Bool {
        return isReloadingReports
    }
    
    /// State management for whether or not the *reports* specifically are reloading.
    public final var isReloadingReports: Bool {
        return _reloadingReports.count > 0
    }
    private var _reloadingReports = Set<ReportQuery>()
    private var _buildingQueries = false
    
    /// Load the reports using the `reportQueries()` for this schedule manager.
    public final func loadReports() {
        DispatchQueue.main.async {
            if self.isReloadingReports || self._buildingQueries { return }
            self._buildingQueries = true
            let queries = self.reportQueries()
            self._reloadingReports.formUnion(queries)
            self._buildingQueries = false
            
            // If there aren't any reports to fetch then exit early.
            guard queries.count > 0 else {
                self.didFinishFetchingReports()
                return
            }
            
            SBAReportManager.offMainQueue.async {
                // Make sure our requested date ranges from "day one" cover the ReportSingletonDate no matter what time zone it was created in.
                // We subtract 2 days because the Bridge endpoint is non-inclusive of the startDate so only subtracting 1 day won't get reports
                // stored with timestamp 2000-12-31T00:00:00.000Z (or date 2000-12-31).
                let dayOne = SBAReportSingletonDate.addingNumberOfDays(-2)
                queries.forEach { (query) in
                    let category = self.reportCategory(for: query.reportIdentifier)
                    do {
                        switch query.queryType {
                        case .mostRecent:
                            let report: SBBReportData = try self.participantManager.getLatestCachedData(forReport: query.reportIdentifier)
                            if !report.isEmpty {
                                self.didFetchReports(for: query, category: category, reports: [report])
                            }
                            else {
                                self.fetchReport(for: query, category: category, startDate: dayOne, endDate: self.now())
                            }
                            
                        case .all:
                            self.fetchReport(for: query, category: category, startDate: dayOne, endDate: self.now())
                            
                        case .today:
                            let end = self.now()
                            let start = end.startOfDay()
                            self.fetchReport(for: query, category: category, startDate: start, endDate: end)
                            
                        case .dateRange:
                            guard let dateRange = query.dateRange else {
                                throw RSDValidationError.unexpectedNullObject("For a `QueryType.dateRange` report query, the `dateRange` property should be non-nil.")
                            }
                            self.fetchReport(for: query, category: category, startDate: dateRange.start, endDate: dateRange.end)
                            
                        }
                    }
                    catch let error {
                        self.didFetchReports(for: query, category: category, reports: nil, error: error)
                    }
                }
            }
        }
    }
    
    // MARK: RSDDataStorageManager
    
    private struct HoldDataKey : Hashable {
        let uuid: UUID
        let identifier: String
        init(_ uuid: UUID, _ identifier: String) {
            self.uuid = uuid
            self.identifier = identifier
        }
    }
    
    private let _holdDataQueue = DispatchQueue(label: "org.sagebionetworks.BridgeApp.SBAReportManager.holdData")
    private var _holdData = [HoldDataKey : RSDTaskData]()
    
    public func previousTaskData(for taskIdentifier: RSDIdentifier) -> RSDTaskData? {
        do {
            if let report = report(with: taskIdentifier.stringValue) {
                return report
            }
            else {
                let sbbReport = try self.participantManager.getLatestCachedData(forReport: taskIdentifier.stringValue)
                let category = self.reportCategory(for: taskIdentifier.stringValue)
                return transformReportData(sbbReport, reportKey: taskIdentifier, category: category)
            }
        }
        catch let err {
            print("WARNING! Failed to query report. \(err)")
        }
        return nil
    }
    
    public func saveTaskData(_ data: RSDTaskData, from taskResult: RSDTaskResult?) {
        
        // If there isn't a task result then save the task data directly to a report.
        guard let uuid = (taskResult as? RSDTaskRunResult)?.taskRunUUID else {
            let report = SBAReport(taskData: data)
            DispatchQueue.main.async {
                self.saveReport(report)
            }
            return
        }
        // Otherwise, save it to a holding dictionary for access later when packaging up all the reports
        // for upload at the same time.
        _holdDataQueue.async {
            self._holdData[HoldDataKey(uuid, data.identifier)] = data
        }
    }
    
    
    // MARK: Data handling

    /// Called on the main thread if updating fails.
    open func updateFailed(_ error: Error) {
        debugPrint("WARNING: Failed to fetch cached objects: \(error)")
    }
    
    /// Find the most recent client data for this activity identifier.
    ///
    /// - parameter activityIdentifier: The activity identifier for the client data associated with this task.
    /// - returns: The client data JSON (if any) associated with this activity identifier.
    @available(*, deprecated)
    open func clientData(with activityIdentifier: String) -> SBBJSONValue? {
        return report(with: activityIdentifier)?.clientData
    }
    
    /// Find the most recent report for this activity identifier.
    ///
    /// - parameter activityIdentifier: The activity identifier for the client data associated with this task.
    /// - returns: The latest report (if any) associated with this activity identifier.
    open func report(with activityIdentifier: String) -> SBAReport? {
        let reportIdentifier = self.reportIdentifier(for: activityIdentifier)
        let report = reports.sorted { (lhs, rhs) -> Bool in
            return lhs.date < rhs.date
            }.last { $0.reportKey == reportIdentifier }
        return report
    }
    
    /// Find the client data within the given date range for this activity identifier.
    ///
    /// - parameter activityIdentifier: The activity identifier for the client data associated with this task.
    /// - returns: The client data JSON (if any) associated with this activity identifier.
    open func allClientData(with activityIdentifier: String, from fromDate: Date = Date.distantPast, to toDate: Date = Date.distantFuture) -> [SBBJSONValue] {
        let reportIdentifier = self.reportIdentifier(for: activityIdentifier)
        return self.reports.compactMap {
            guard $0.reportKey == reportIdentifier,
                (fromDate <= $0.date && $0.date < toDate)
                else {
                    return nil
            }
            return $0.clientData
        }
    }
    
    /// Return the report identifier for a given activity identifier.
    open func reportIdentifier(for activityIdentifier: String) -> String {
        return self.configuration.schemaInfo(for: activityIdentifier)?.schemaIdentifier ?? activityIdentifier
    }
    
    /// Get the report category (if any defined) for the given identifier. Default calls through to
    /// `SBABridgeConfiguration` and returns `.timestamp` if undefined by the configuration.
    open func reportCategory(for reportIdentifier: String) -> SBAReportCategory {
        return self.configuration.reportCategory(for: reportIdentifier) ?? .timestamp
    }
    
    func addReports(with newReports: [SBAReport], for query: ReportQuery? = nil) {
        
        var updatedReports = [SBAReport]()
        if query != nil {
            self.unionReports(newReports, query: query!)
            updatedReports.append(contentsOf: newReports)
        }
        else {
            let queries = self.reportQueries()
            queries.forEach {
                let filteredReports = self.filteredReports(newReports, query: $0)
                self.unionReports(filteredReports, query: $0)
                updatedReports.append(contentsOf: filteredReports)
            }
        }
        
        self.didUpdateReports(with: updatedReports)
    }

    func filteredReports( _ newReports: [SBAReport], query: ReportQuery) -> [SBAReport] {
        return newReports.filter { (report) -> Bool in
            guard query.reportKey == report.reportKey else { return false }
            switch query.queryType {
            case .today:
                return report.date.isToday
                
            case .dateRange:
                guard let dateRange = query.dateRange else { return false }
                return dateRange.start <= report.date && report.date <= dateRange.end
                
            default:
                return true
            }
        }
    }
    
    func unionReports(_ newReports: [SBAReport], query: ReportQuery) {
        guard newReports.count > 0 else { return }
        if query.queryType == .mostRecent,
            let previous = self.reports.first(where: { $0.reportKey == query.reportKey }),
            newReports.count == 1 {
            self.reports.remove(previous)
        }
        self.reports.formUnion(newReports)
    }
    
    /// Post notification that the reports were updated.
    open func didUpdateReports(with newReports: [SBAReport]) {
        NotificationCenter.default.post(name: .SBAUpdatedReports,
                                        object: self,
                                        userInfo: [NotificationKey.newReports: newReports])
    }
    
    /// Build and save the report `clientData` for the completed task. This should only be called for the
    /// top-level path.
    ///
    /// - parameter taskViewModel: The task path for the task which has just run.
    public func saveReports(for taskViewModel: RSDTaskViewModel) {
        guard taskViewModel.parent == nil else {
            assertionFailure("This method should **only** be called for the top-level task path.")
            return
        }
        
        // Exit early if there are no reports for this task.
        guard let newReports = buildReports(from: taskViewModel.taskResult) else { return }
        
        // Post notification that reports have been created.
        NotificationCenter.default.post(name: .SBAWillSaveReports,
                                        object: self,
                                        userInfo: [NotificationKey.newReports: newReports])
        
        // Save each report to Bridge.
        newReports.forEach { (report) in
            self.saveReportToBridge(report)
        }
    }
    
    /// Save an individual new report.
    ///
    /// - parameter report: The report object to save.
    public func saveReport(_ report: SBAReport) {
        // Post notification that a report has been created.
        NotificationCenter.default.post(name: .SBAWillSaveReports,
                                        object: self,
                                        userInfo: [NotificationKey.newReports: [report]])
        
        // Save the report to Bridge.
        self.saveReportToBridge(report)
    }
    
    /// Save an individual report to Bridge.
    ///
    /// - parameter report: The report object to save to Bridge.
    public func saveReportToBridge(_ report: SBAReport) {
        let reportIdentifier = report.reportKey.stringValue
        let category = self.reportCategory(for: reportIdentifier)
        let bridgeReport = SBBReportData()

        switch category {
        case .timestamp:
            
            // The report date returned from the server does not include the time zone identifier.
            // While we can infer a timezone from the GMT offset, we don't get information such as
            // "PDT" (Pacific Daylight Time) that may be displayed to the user. syoung 10/04/2019
            var json = [String : Any]()
            json[kReportClientDataKey] = report.clientData
            json[kReportTimeZoneIdentifierKey] = report.timeZone.identifier
            let formatter = NSDate.iso8601formatter()!
            formatter.timeZone = report.timeZone
            let dateString = formatter.string(from: report.date)
            json[kReportDateKey] = dateString
            
            // Set the report date using ISO8601 with the time zone information.
            bridgeReport.dateTime = dateString
            bridgeReport.data = json as NSDictionary
            
        case .singleton:
            
            // For a singleton, always set the date to a dateString that is the singleton date
            // in UTC timezone. This way it will always write to the report using that date.
            bridgeReport.data = report.clientData
            let formatter = NSDate.iso8601DateOnlyformatter()!
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let reportDate = self.date(for: reportIdentifier, from: report.date)
            bridgeReport.localDate = formatter.string(from: reportDate)
            
        case .groupByDay:
            
            // For grouped by day, the date is the date in the report timezone.
            bridgeReport.data = report.clientData
            let formatter = NSDate.iso8601DateOnlyformatter()!
            formatter.timeZone = report.timeZone
            bridgeReport.localDate = formatter.string(from: report.date)
        }
        
        self.participantManager.save(bridgeReport, forReport: reportIdentifier) { (_, error) in
            guard let error = error else { return }
            print("Failed to save report: \(error)")
        }
    }
    
    /// Build the reports to return for this task result.
    open func buildReports(from topLevelResult: RSDTaskResult) -> [SBAReport]? {
        
        // Recursively build a report for all the schemas in this task path.
        var newReports = [SBAReport]()
        func appendReports(_ taskResult: RSDTaskResult, _ level: Int) {
            let topResult = (level == 0) ? nil : topLevelResult
            if let reportIdentifier = self.reportIdentifier(for: taskResult, topLevelResult: topResult),
                let clientData = buildClientData(from: taskResult) {
                
                // Look to see if there are multiple levels with the same JSON identifier and
                // return the merged client data from them.
                let reportKey = RSDIdentifier(rawValue: reportIdentifier)
                if let previousReport = newReports.remove(where: { $0.reportKey == reportKey }).first {
                    if let newJson = clientData as? [String: Any],
                        let previousJson = previousReport.clientData as? [String: Any] {
                        let mergedJson = previousJson.merging(newJson) { (previous, _) in previous }
                        let report = SBAReport(reportKey: reportKey,
                                               date: previousReport.date,
                                               clientData: mergedJson as NSDictionary,
                                               timeZone: previousReport.timeZone)
                        newReports.append(report)
                    }
                    else {
                        newReports.append(previousReport)
                    }
                }
                else {
                    let jsonData: SBBJSONValue = {
                        guard let newJSON = clientData as? [String: Any] else { return clientData }
                        var json = newJSON
                        json[SBATaskRunUUIDKey] = (taskResult as? RSDTaskRunResult)?.taskRunUUID.uuidString
                        return json as NSDictionary
                    }()
                    let report = newReport(reportIdentifier: reportIdentifier, date: taskResult.endDate, clientData: jsonData)
                    newReports.append(report)
                }
            }
            taskResult.stepHistory.forEach {
                guard let subtaskResult = $0 as? RSDTaskResult else { return }
                appendReports(subtaskResult, level + 1)
            }
        }
        appendReports(topLevelResult, 0)
        
        return newReports.count > 0 ? newReports : nil
    }
    
    open func newReport(reportIdentifier: String, date: Date, clientData: SBBJSONValue) -> SBAReport {
        
        let category = self.reportCategory(for: reportIdentifier)
        let reportDate = self.date(for: reportIdentifier, from: date)
        let timeZone: TimeZone = {
            switch category {
            case .singleton:
                return TimeZone(secondsFromGMT: 0)!
                
            case .groupByDay:
                return TimeZone.current

            case .timestamp:
                return TimeZone.current
            }
        }()
        
        return SBAReport(reportKey: RSDIdentifier(rawValue: reportIdentifier),
            date: reportDate,
            clientData: clientData,
            timeZone: timeZone)
    }
    
    /// The report identifier to use for the given task result. If the `topLevelResult` is non-nil
    /// then this task result is a subtask of another result.
    open func reportIdentifier(for taskResult: RSDTaskResult, topLevelResult: RSDTaskResult?) -> String? {
        let schemaInfo = (taskResult as? RSDTaskRunResult)?.schemaInfo ?? self.schemaInfo(for: taskResult.identifier)
        return schemaInfo?.schemaIdentifier
    }
    
    /// The date to use for the report with the given identifier.
    public final func date(for reportIdentifier: String, from result: RSDTaskResult) -> Date {
        return self.date(for: reportIdentifier, from: result.endDate)
    }
    
    /// Convert the input date for the report into the appropriate date to use for the report
    /// category (singleton, group by day, or timestamp).
    public final func date(for reportIdentifier: String, from date: Date) -> Date {
        let category = self.reportCategory(for: reportIdentifier)
        switch category {
        case .singleton:
            
            // Singleton reports can overwrite an existing report, so check for a previous report
            // and use that report date instead so that it remains a singleton.
            // That said, there are a number of calls to saveReports() that do not correctly
            // set the report date to the singleton instance, so we need to check against the
            // most recent date stamp and use that if there is one.
            let previousReport = self.reports
                .sorted(by: { $0.date < $1.date })
                .last(where: { $0.identifier == reportIdentifier })
            let reportDate = previousReport?.date ?? SBAReportSingletonDate
            return reportDate
            
        case .groupByDay:
            return date.startOfDay()
        case .timestamp:
            return date
        }
    }
    
    /// Build the client data from the given task path.
    ///
    /// - parameters:
    ///     - taskResult: The task result for the task which has just run.
    /// - returns: The client data built for this task result (if any).
    open func buildClientData(from taskResult: RSDTaskResult) -> SBBJSONValue? {
        
        // Get the hold data, if any.
        var holdJSON: JsonSerializable?
        _holdDataQueue.sync {
            if let uuid = (taskResult as? RSDTaskRunResult)?.taskRunUUID {
                let key = HoldDataKey(uuid, taskResult.identifier)
                holdJSON = self._holdData[key]?.json
                self._holdData[key] = nil
            }
        }
        
        // For now, assume that if there is data from the task, that that scoring is all we need. Eventually,
        // this might need to incorporate adding to that data, but don't build that into the function until
        // we discover a need for it. syoung 05/08/2019
        if let json = holdJSON {
            return json.toClientData()
        }
        
        // Otherwise, use a default builder for the scoring.
        let builder = RSDDefaultScoreBuilder()
        return builder.getScoringData(from: taskResult)?.toClientData()
    }
    
    /// This is no longer used by the report manager to build a report. syoung 05/07/2019
    @available(*, unavailable)
    open func buildSurveyAnswerMap(from taskResult: RSDTaskResult) -> [String : Any] {
        fatalError("Do not override this method - it is no longer used.")
    }
    
    func fetchReport(for query: ReportQuery, category: SBAReportCategory, startDate: Date, endDate: Date) {
        let category = self.reportCategory(for: query.reportIdentifier)
        
        switch category {
        case .timestamp:
            self.participantManager.getReport(query.reportIdentifier, fromTimestamp: startDate, toTimestamp: endDate) { [weak self] (obj, error) in
                self?.didFetchReports(for: query, category: category, reports: obj as? [SBBReportData], error: error)
            }
            
        case .groupByDay:
            // The report date on groupByDay reports will be at the start of a day, and the Bridge endpoint for retrieving reports appears
            // to be non-inclusive for the startDate parameter, so we need to fudge it a bit to make sure we include the report for startDate.
            self.participantManager.getReport(query.reportIdentifier, fromDate: startDate.startOfDay().addingTimeInterval(-1.0).dateOnly(), toDate: endDate.addingNumberOfDays(1).startOfDay().dateOnly()) { [weak self] (obj, error) in
                
                self?.didFetchReports(for: query, category: category, reports: obj as? [SBBReportData], error: error)
            }
            
        case .singleton:
            // Make sure we cover the ReportSingletonDate no matter what time zone or BridgeApp version it was created in
            // and no matter what time zone it's being retrieved in:
            let fromDateComponents = Date(timeIntervalSince1970: -48 * 60 * 60).dateOnly()
            let toDateComponents = Date(timeIntervalSinceReferenceDate: 48 * 60 * 60).dateOnly()
            self.participantManager.getReport(query.reportIdentifier, fromDate: fromDateComponents, toDate: toDateComponents) { [weak self] (obj, error) in
                self?.didFetchReports(for: query, category: category, reports: obj as? [SBBReportData], error: error)
            }
        }
    }
    
    func didFetchReports(for query: ReportQuery, category: SBAReportCategory, reports inReports: [SBBReportData]?, error inError: Error? = nil) {
        
        let reportDataObjects: [SBBReportData] = {
            guard let response = inReports, query.queryType == .mostRecent, response.count > 0
                else {
                    return inReports ?? []
            }
            let report = response.sorted { (lhs, rhs) -> Bool in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else { return false }
                return lhsDate < rhsDate
                }.last!
            return [report]
        }()

        let newReports: [SBAReport] = reportDataObjects.compactMap {
            transformReportData($0, reportKey: query.reportKey, category: category)
        }
        
        let error: Error? = {
            if inError != nil || inReports != nil {
                return inError
            }
            else {
                return RSDValidationError.unexpectedNullObject("Error and response are both nil for \(query)")
            }
        }()
        
        DispatchQueue.main.async {
            if let err = error {
                self.updateFailed(err)
            }
            else {
                self.addReports(with: newReports, for: query)
            }
            self._reloadingReports.remove(query)
            if self._reloadingReports.count == 0 {
                self.didFinishFetchingReports()
            }
        }
    }
    
    open func transformReportData(_ report: SBBReportData, reportKey: RSDIdentifier, category: SBAReportCategory) -> SBAReport? {
        guard let reportData = report.data, let date = report.date else { return nil }
        
        if let json = reportData as? [String : Any],
            let clientData = json[kReportClientDataKey] as? SBBJSONValue,
            let dateString = json[kReportDateKey] as? String,
            let timeZoneIdentifier = json[kReportTimeZoneIdentifierKey] as? String {
            let reportDate = self.factory.decodeDate(from: dateString) ?? date
            let timeZone = TimeZone(identifier: timeZoneIdentifier) ??
                TimeZone(iso8601: dateString) ??
                TimeZone.current
            return SBAReport(reportKey: reportKey, date: reportDate, clientData: clientData, timeZone: timeZone)
        }
        else {
            switch category {
            case .timestamp, .groupByDay:
                return SBAReport(reportKey: reportKey, date: date, clientData: reportData, timeZone: TimeZone.current)
                
            case .singleton:
                let timeZone = TimeZone(secondsFromGMT: 0)!
                let reportDate: Date = {
                    if let localDate = report.localDate {
                        let dateFormatter = NSDate.iso8601DateOnlyformatter()!
                        dateFormatter.timeZone = timeZone
                        return dateFormatter.date(from: localDate) ?? date
                    }
                    else {
                        return date
                    }
                }()
                return SBAReport(reportKey: reportKey, date: reportDate, clientData: reportData, timeZone: timeZone)
            }
        }
    }
    
    /// Called when all the reports are finished loading. Base class does nothing.
    open func didFinishFetchingReports() {
    }
}

extension SBBReportData {
    
    var isEmpty: Bool {
        return data == nil && date == nil
    }
}
