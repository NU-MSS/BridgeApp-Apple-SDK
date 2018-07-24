//
//  SBATrackedItemsStepNavigator.swift
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

/// `SBATrackedItemsStepNavigator` is a general-purpose navigator designed to be used for selecting tracked
/// data such as medication, triggers, or symptoms.
open class SBATrackedItemsStepNavigator : Decodable, RSDTrackingStepNavigator {

    /// Publicly accessible coding keys for the default structure for decoding items and sections.
    public enum ItemsCodingKeys : String, CodingKey {
        case items, sections
    }
    
    /// Publicly accessible coding keys for the steps used by this navigator.
    public enum StepIdentifiers : String, CodingKey {
        case selection, review, addDetails, logging, reminder
    }
    
    public enum RequiredStepCodingKeys : String, CodingKey {
        case identifier, type
    }
    
    private enum TaskCodingKeys : String, CodingKey {
        case activityIdentifier = "identifier"
    }
    
    /// The activity identifier associated with this tracked items.
    public let activityIdentifier: RSDIdentifier
    
    /// The list of medications.
    public var items: [SBATrackedItem] {
        return self.selectionStep.items
    }
    
    /// The section items for mapping each medication.
    public var sections: [SBATrackedSection]? {
        return self.selectionStep.sections
    }
    
    /// Replace the items and sections on selection, logging, and review steps.
    /// - parameters:
    ///     - items: The list of medications.
    ///     - sections: The section items for mapping each medication.
    open func set(items: [SBATrackedItem], sections: [SBATrackedSection]?) {
        self.selectionStep.sections = sections
        self.selectionStep.items = items
        self.reviewStep?.sections = sections
        self.reviewStep?.items = items
        self.loggingStep.sections = sections
        self.loggingStep.items = items
    }
    
    /// A previous result that can be used to pre-populate the data set.
    public internal(set) var previousClientData: SBBJSONValue? {
        didSet {
            // If the previous result is set to a non-nil value then use that as the in-memory result.
            if let clientData = previousClientData {
                try? _inMemoryResult.updateSelected(from: clientData, with: self.items)
            }
        }
    }
    
    /// The task path associated with the current run of the task.
    public private(set) weak var taskPath: RSDTaskPath?
    
    /// Setup data tracking for this task.
    open func setupTracking(with taskPath: RSDTaskPath) {
        self.taskPath = taskPath
        guard let scheduleManager = taskPath.trackingDelegate as? SBAScheduleManager,
            let clientData = scheduleManager.clientData(with: self.activityIdentifier.stringValue)
            else {
                return
        }
        self.previousClientData = clientData
    }
    
    /// Default initializer.
    /// - parameters:
    ///     - items: The list of medications.
    ///     - sections: The section items for mapping each medication.
    public required init(identifier: String, items: [SBATrackedItem], sections: [SBATrackedSection]? = nil) {
        self.activityIdentifier = RSDIdentifier(rawValue: identifier)
        self.selectionStep = type(of: self).buildSelectionStep(items: items, sections: sections)
        self.reviewStep = type(of: self).buildReviewStep(items: items, sections: sections)
        self.detailStepTemplates = type(of: self).buildDetailSteps(items: items, sections: sections)
        self.loggingStep = type(of: self).buildLoggingStep(items: items, sections: sections)
        self.reminderStep = type(of: self).buildReminderStep()
    }
    
    
    // MARK: Decodable
    
    /// Decoding uses the default steps from the class build functions, and then overwrites
    /// properties found in the decoder. Currently, this assumes that the steps inherit from
    /// `RSDUIStepObject`
    public required init(from decoder: Decoder) throws {
        let taskContainer = try decoder.container(keyedBy: TaskCodingKeys.self)
        self.activityIdentifier = try taskContainer.decode(RSDIdentifier.self, forKey: .activityIdentifier)
        
        let (items, sections) = try type(of: self).decodeItems(from: decoder)
        
        // Build the details template.
        let container = try decoder.container(keyedBy: StepIdentifiers.self)
        let detailStepTemplates = type(of: self).buildDetailSteps(items: items, sections: sections)
        if let step = detailStepTemplates?.first as? RSDDecodableReplacement, container.contains(.addDetails) {
            let nestedDecoder = try container.superDecoder(forKey: .addDetails)
            try step.decode(from: nestedDecoder)
        }
        
        // Build the tracking steps.
        let selectionStep = try type(of: self).decodeStep(from: decoder, for: .selection, items: items, sections: sections)
        let reviewStep = try type(of: self).decodeStep(from: decoder, for: .review, items: items, sections: sections)
        let loggingStep = try type(of: self).decodeStep(from: decoder, for: .logging, items: items, sections: sections)
        
        self.selectionStep = selectionStep!
        self.reviewStep = reviewStep
        self.detailStepTemplates = detailStepTemplates
        self.loggingStep = loggingStep!
        
        // Build the decoder optional reminder step
        var reminderStepDecoded: SBATrackedItemRemindersStepObject?
        if container.contains(.reminder) {
            let nestedDecoder = try container.superDecoder(forKey: .reminder)
            reminderStepDecoded = try decoder.factory.decodeStep(from: nestedDecoder) as? SBATrackedItemRemindersStepObject
        }
        let reminderStepBuild = type(of: self).buildReminderStep()
        self.reminderStep = (reminderStepDecoded ?? reminderStepBuild)?.copy(with: RSDIdentifier.medicationReminders.stringValue)
    }
    
    open class func decodeItems(from decoder: Decoder) throws -> (items: [SBATrackedItem], sections: [SBATrackedSection]?) {
        let container = try decoder.container(keyedBy: ItemsCodingKeys.self)
        let items = try container.decode([SBATrackedItemObject].self, forKey: .items)
        let sections = try container.decodeIfPresent([SBATrackedSectionObject].self, forKey: .sections)
        return (items, sections)
    }
    
    // MARK: Step management
    
    /// The selection step to use to model selecting the medication.
    public let selectionStep: SBATrackedItemsStep
    
    /// The review step to display when reviewing/editing selected medication.
    public let reviewStep: SBATrackedItemsStep?
    
    /// The detail step should be displayed for each tracked item that has additional details.
    public let detailStepTemplates: [SBATrackedItemDetailsStep]?
    
    /// A step to display in order to log details for a set of tracked data. For example, as well
    /// as logging a user's medication, the researchers may wish to log whether or not the participant
    /// took the medication when scheduled to do so.
    public let loggingStep: SBATrackedItemsStep
    
    /// The reminder step to display when the user chooseg when they should be reminded about the tracked items.
    public let reminderStep: SBATrackedItemRemindersStepObject?
    
    /// Build the selection step for this tracked data collection. Override to customize the step.
    open class func buildSelectionStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep {
        let stepId = StepIdentifiers.selection.stringValue
        let step = SBATrackedSelectionStepObject(identifier: stepId, items: items, sections: sections)
        return step
    }
    
    /// Build the review step for this tracked data collection. Override to customize the step.
    open class func buildReviewStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep? {
        return nil
    }
    
    /// Build the add details steps for this tracked data collection. Override to customize the steps.
    open class func buildDetailSteps(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> [SBATrackedItemDetailsStep]? {
        return nil
    }
    
    /// Build the logging step for this tracked data collection. Override to customize the step.
    open class func buildLoggingStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep {
        let stepId = StepIdentifiers.logging.stringValue
        return SBATrackedItemsLoggingStepObject(identifier: stepId, items: items, sections: sections, type: .logging)
    }
    
    /// Build the reminder step for this tracked data collection. Override to customize the step.
    open class func buildReminderStep() -> SBATrackedItemRemindersStepObject? {
        return nil
    }
    
    private class func decodeStep(from decoder: Decoder, for identifier: StepIdentifiers, items: [SBATrackedItem], sections: [SBATrackedSection]?) throws -> SBATrackedItemsStep? {
        
        // Check if the decoder contains a step keyed by the identifier otherwise exit early.
        let container = try decoder.container(keyedBy: StepIdentifiers.self)
        guard container.contains(identifier) else {
            return buildStep(identifier: identifier, items: items, sections: sections)
        }
        
        // Look to see if this should be decoded using the factory.
        let nestedDecoder = try container.superDecoder(forKey: identifier)
        if let _ =  try decoder.factory.typeName(from: nestedDecoder) {
            let step = try decoder.factory.decodeStep(from: nestedDecoder)
            if let trackingStep = step as? SBATrackedItemsStep {
                // If the decoded step is of the expected type then set the items and sections and
                // return the step decoded by the decoder.
                trackingStep.items = items
                trackingStep.sections = sections
                return trackingStep
            }
            else {
                let context = DecodingError.Context(codingPath: nestedDecoder.codingPath, debugDescription: "Failed to cast the decoded step to a `SBATrackedItemsStep`")
                throw DecodingError.typeMismatch(SBATrackedItemsStep.self, context)
            }
        }
        else {
            // Build the step and decode into it if possible (if cannot decode the step from the factory)
            let step = buildStep(identifier: identifier, items: items, sections: sections)
            if let dStep = step as? RSDDecodableReplacement {
                try dStep.decode(from: nestedDecoder)
            }
            return step
        }
    }
    
    private class func buildStep(identifier: StepIdentifiers, items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep? {
        switch identifier {
        case .selection:
            return buildSelectionStep(items: items, sections: sections)
        case .logging:
            return buildLoggingStep(items: items, sections: sections)
        case .review:
            return buildReviewStep(items: items, sections: sections)
        default:
            return nil
        }
    }
    
    // MARK: Result management
    
    /// The in-memory result is the stored result that is used to set the current state before
    /// displaying any steps.
    lazy private var _inMemoryResult: SBATrackedItemsCollectionResult = {
        return instantiateLoggingResult()
    }()
    
    /// Updates the in-memory result that is used to track the selection state.
    ///
    /// - parameters:
    ///     - taskResult: The current task result.
    ///     - previousStep: The previous step that was displayed and is triggering calling this function
    func updateInMemoryResult(from taskResult: inout RSDTaskResult, using previousStep: RSDStep?) {
        
        guard let step = previousStep,
            let result = taskResult.findResult(for: step) else {
            return
        }
        
        if let removeItemResult = result as? SBARemoveTrackedItemsResultObject {
            self.updateSelectedInMemoryResult(byRemoving: removeItemResult.items.map({ $0.identifier }))
        }
        else if step.identifier == self.selectionStep.identifier {
            let selectedIdentifiers = (result as? SBATrackedItemsResult)?.selectedIdentifiers
            self.updateSelectedInMemoryResult(to: selectedIdentifiers, with: self.items)
        }
        else if let reviewStep = self.reviewStep, step.identifier == reviewStep.identifier {
            if let newResult = taskResult.findResult(for: reviewStep) as? SBATrackedItemsCollectionResult {
                _inMemoryResult = newResult
            }
            else {
                assertionFailure("Expecting the review step to have a SBATrackedItemsCollectionResult.")
            }
        }
        else {
            _inMemoryResult.updateDetails(from: result)
        }
        
        taskResult.appendAsyncResult(with: _inMemoryResult.copy(with: self.activityIdentifier.rawValue))
    }
    
    /// Update the selected items for the in-memory result by removing the items with the selected identifiers.
    func updateSelectedInMemoryResult(byRemoving identifiers: [String]?) {
        guard let identifiersToRemove = identifiers else { return }
        let selectedIdentifiers = _inMemoryResult.selectedIdentifiers
        let newIdentifiers = selectedIdentifiers.filter({ !identifiersToRemove.contains($0) })
        self.updateSelectedInMemoryResult(to: newIdentifiers, with: self.items)
    }
    
    /// Update the selected items for the in-memory result.
    func updateSelectedInMemoryResult(to selectedIdentifiers: [String]?, with items: [SBATrackedItem]) {
        _inMemoryResult.updateSelected(to: selectedIdentifiers, with: self.items)
    }
    
    /// Instantiate the appropriate result that can be used for logging and review.
    open func instantiateLoggingResult() -> SBATrackedItemsCollectionResult {
        return SBATrackedLoggingCollectionResultObject(identifier: self.loggingStep.identifier)
    }
    
    // MARK: Detail step management
    
    private var _detailSteps: [String : RSDStep] = [:]

    /// Find or copy the detail step specific to this identifier.
    open func getDetailStep(with identifier: String) -> (RSDStep, SBATrackedItemAnswer)? {
        guard let selectedAnswer = _inMemoryResult.selectedAnswers.first(where: { $0.identifier == identifier}),
            let item = (self.items.first(where: { $0.identifier == identifier}) ?? (selectedAnswer as? SBATrackedItem)),
            let detailsId = item.addDetailsIdentifier
            else {
                return nil
        }
        if let step = _detailSteps[identifier] {
            if let detailStep = step as? SBATrackedItemDetailsStepObject {
                detailStep.updatePreviousAnswer(answer: selectedAnswer)
            }
            // return the previously created instance if there is one.            
            return (step, selectedAnswer)
        } else if let template = self.detailStepTemplates?.first(where: { $0.identifier == detailsId }),
            let step = template.copy(from: item, with: selectedAnswer) {
            // save the created step for future calls.
            _detailSteps[identifier] = step
            return (step, selectedAnswer)
        } else {
            return nil
        }
    }
    
    /// Get the next detail step that still has details to fill in.
    open func nextDetailStep(after identifier: String, result: RSDTaskResult) -> RSDStep? {
        guard !_inMemoryResult.hasRequiredValues else { return nil }

        // If the tracked item was removed, there should be no next detail step.
        guard !isRemoveTrackedItemResult(with: identifier, result: result) else { return nil }
        
        return _nextDetailStep(after: identifier, previousLoop: nil)
    }
    
    func _nextDetailStep(after identifier: String, previousLoop: String?) -> RSDStep? {
        let selectedIdentifiers = _inMemoryResult.selectedIdentifiers
        guard selectedIdentifiers.count > 0 else { return nil }
        
        var previousId = identifier
        // If the previous identifier isn't in the list of selected identifiers,
        // then look to see if if it needs its details set
        if !selectedIdentifiers.contains(previousId) {
            previousId = selectedIdentifiers.first!
            if let (step, answer) = getDetailStep(with: previousId), !answer.hasRequiredValues {
                return step
            }
        }
        // Look forward to the next identifier that isn't filled.
        while let nextId = selectedIdentifiers.rsd_next(after: { $0 == previousId }), nextId != previousLoop {
            previousId = nextId
            if let (step, answer) = getDetailStep(with: nextId), !answer.hasRequiredValues {
                return step
            }
        }
        // If the starting identifier is the review, this has looped before, or there is only one selected
        // item, then we know we have gotten them all. Otherwise, go back to the beginning and loop through.
        if previousLoop != nil || selectedIdentifiers.count == 1 || !selectedIdentifiers.contains(identifier) {
            return nil
        } else {
            return _nextDetailStep(after: self.reviewStep?.identifier ?? "null", previousLoop: identifier)
        }
    }
    
    /// Get the selection step including any preparation required for this navigator.
    open func getSelectionStep() -> RSDStep {
        self.selectionStep.result = _inMemoryResult
        return self.selectionStep
    }
    
    /// Get the review step including any preparation required for this navigation.
    open func getReviewStep() -> RSDStep? {
        self.reviewStep?.result = _inMemoryResult
        return self.reviewStep
    }
    
    /// Get the logging step including any preparation required for this navigation.
    open func getLoggingStep() -> RSDStep {
        self.loggingStep.result = _inMemoryResult
        return self.loggingStep
    }
    
    // MARK: RSDStepNavigator
    
    /// Should the given step be skipped?
    ///
    /// By default, the step should be skipped if and only if this is a task that is included as a subtask
    /// of another task (such as including medication logging in a tapping test) **and** the skip rule
    /// on the step returns true or there are no selected answers.
    open func shouldSkip(step: RSDStep?, with result: RSDTaskResult) -> Bool {
        if self.taskPath?.parentPath != nil,
            let navigableStep = step as? RSDNavigationSkipRule {
            return navigableStep.shouldSkipStep(with: result, conditionalRule: nil, isPeeking: false)
        }
        else {
            return false
        }
    }
    
    /// If this is a selection or review identifier, those steps are returned, otherwise
    /// will return the appropriate detail step for the given item identifier (if any).
    open func step(with identifier: String) -> RSDStep? {
        if identifier == self.selectionStep.identifier {
            return getSelectionStep()
        } else if identifier == self.reviewStep?.identifier {
            return getReviewStep()
        } else if identifier == self.loggingStep.identifier {
            return getLoggingStep()
        } else if let (step, _) = getDetailStep(with: identifier) {
            return step
        } else {
            return nil
        }
    }
    
    /// Returns `false`.
    open func shouldExit(after step: RSDStep?, with result: RSDTaskResult) -> Bool {
        return false
    }
    
    /// Returns `true` unless this is a logging step or review step with all information completed.
    open func hasStep(after step: RSDStep?, with result: RSDTaskResult) -> Bool {
        // There is always a first step. If nil, then return `true`.
        guard let identifier = step?.identifier else { return true }
        
        // Logging is always the last step.
        if identifier == self.loggingStep.identifier { return false }
        
        // If this is not a review step then there will always be a step after b/c the
        // review step (or logging step) is always last.
        if identifier != reviewStep?.identifier { return true }
        
        // There is a step after the review step if it does not have all required values.
        return !_inMemoryResult.hasRequiredValues
    }
    
    /// Returns `false` if and only if this is the selection or review step.
    open func hasStep(before step: RSDStep, with result: RSDTaskResult) -> Bool {
        if step.identifier == self.selectionStep.identifier ||
            step.identifier == self.reviewStep?.identifier ||
            step.identifier == self.loggingStep.identifier {
            return false
        } else {
            return true
        }
    }
    
    /// The next step in the series depends upon what information is remaining to be entered.
    open func step(after step: RSDStep?, with result: inout RSDTaskResult) -> (step: RSDStep?, direction: RSDStepDirection) {
        var nextStep = _step(after: step, with: &result)
        if shouldSkip(step: nextStep, with: result) {
            nextStep = nil
        }
        let navigationDirection = _navigationDirection(for: step, result: result)
        return (nextStep, navigationDirection)
    }
    
    private func _step(after step: RSDStep?, with result: inout RSDTaskResult) -> RSDStep? {
        
        // When moving forward, always update the in-memory result before continuing.
        updateInMemoryResult(from: &result, using: step)
        
        guard let identifier = step?.identifier else {
            // For the first step, return the logging step if there is a valid previous result.
            // Otherwise, return the selection step.
            if (previousClientData != nil), _inMemoryResult.selectedAnswers.count > 0 {
                return getLoggingStep()
            } else {
                return getSelectionStep()
            }
        }
        
        var nextStepPerNavigationRule: RSDStep?
        if let navStep = step as? RSDNavigationRule,
            let nextId = navStep.nextStepIdentifier(with: result, conditionalRule: nil, isPeeking: false),
            let nextStep = self.step(with: nextId) {
            nextStepPerNavigationRule = nextStep
        }
        
        // If this is a logging step, it is always the last step, unless the navigation rule suggests otherwise.
        if identifier == self.loggingStep.identifier {
            if let nextStep = nextStepPerNavigationRule {
                return nextStep
            }
            return nil
        }

        // If there is no review step then this should return the logging step.
        guard let reviewStep = getReviewStep() else {
            return getLoggingStep()
        }
        
        if identifier == self.selectionStep.identifier {
            // Selection is always followed by review.
            return reviewStep
        } else if identifier == reviewStep.identifier,
            let nextStep = nextStepPerNavigationRule {
            // If the review step has implemented custom navigation to go to a specific step, then
            // repect that navigation rule.
            return nextStep
        } else if let nextStep = self.nextDetailStep(after: identifier, result: result) {
            // If there is a step that doesn't have details added then return that.
            return nextStep
        } else if identifier == self.reminderStep?.identifier {
            // Exit.
            return nil
        } else if identifier != reviewStep.identifier {
            // If there are no items to review, go back to the selection step.
            if self._inMemoryResult.selectedIdentifiers.count == 0 {
                return selectionStep
            }
            // If this is *not* the review step then we are done adding details, so
            // return the review step.
            return reviewStep
        } else {
            // At this point we can assume that the previous step was the review step.
            if previousClientData != nil {
                // If we have existing client data, we can assume the user should go to logging next.
                return getLoggingStep()
            } else if let reminderStepUnwrapped = self.reminderStep {
                return reminderStepUnwrapped
            }
            // Exit.
            return nil
        }
    }
    
    private func _navigationDirection(for step: RSDStep?, result: RSDTaskResult) -> RSDStepDirection {
        // If the tracked item was removed, we should navigate in the reverse direction.
        if isRemoveTrackedItemResult(with: step?.identifier, result: result) {
            return .reverse
        }
        return .forward
    }
    
    /// Going back should always return to the review step (unless this *is* selection or review).
    open func step(before step: RSDStep, with result: inout RSDTaskResult) -> RSDStep? {
        guard let reviewStep = self.reviewStep else { return nil }
        if step.identifier == self.selectionStep.identifier ||
            step.identifier == reviewStep.identifier ||
            step.identifier == self.loggingStep.identifier {
            return nil
        } else {
            return self.reviewStep
        }
    }
    
    /// Returns `nil`. Progress is not used by default.
    open func progress(for step: RSDStep, with result: RSDTaskResult?) -> (current: Int, total: Int, isEstimated: Bool)? {
        return nil
    }
    
    fileprivate func isRemoveTrackedItemResult(with identifier: String?, result: RSDTaskResult) -> Bool {
        if let identifierUnwrapped = identifier {
            return (result.findResult(with: identifierUnwrapped) as? SBARemoveTrackedItemsResultObject) != nil
        }
        return false
    }
}
