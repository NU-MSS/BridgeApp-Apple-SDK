//
//  MedicationLoggingDataSourceTests.swift
//  BridgeAppTests
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

import XCTest
@testable import BridgeApp
@testable import DataTracking
import ResearchUI

class MedicationLoggingDataSourceTests: XCTestCase {

    override func setUp() {
        super.setUp()

        NSLocale.setCurrentTest(Locale(identifier: "en_US"))
        LocalizationBundle.registerDefaultBundlesIfNeeded()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAvailableMeds_Morning_NoMedsTaken_EveryDay() {
        var medA3 = SBAMedicationAnswer(identifier: "medA3")
        let timestamps = ["08:00", "12:00", "20:00"].map { SBATimestamp(timeOfDay: $0, loggedDate: nil) }
        let dose = SBADosage(dosage: "10 mg",
                             daysOfWeek: RSDWeekday.all,
                             timestamps: timestamps,
                             isAnytime: false)
        medA3.dosageItems = [dose]

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 0)
        guard let medTiming = medA3.availableMedications(at: timeOfDay) else {
            XCTFail("Unexpected nil")
            return
        }

        XCTAssertEqual(medTiming.currentItems.count, 1)
        XCTAssertEqual(medTiming.missedItems.count, 0)
    }

    func testAvailableMeds_Morning_MedsTaken_EveryDay() {
        var medA3 = SBAMedicationAnswer(identifier: "medA3")
        let timestamps = ["08:00", "12:00", "20:00"].map { SBATimestamp(timeOfDay: $0,
                                                                        loggedDate: self.buildDate(weekday: .monday, hour: 8, minute: 0)) }
        let dose = SBADosage(dosage: "10 mg",
                             daysOfWeek: RSDWeekday.all,
                             timestamps: timestamps,
                             isAnytime: false)
        medA3.dosageItems = [dose]

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 0)
        guard let medTiming = medA3.availableMedications(at: timeOfDay) else {
            XCTFail("Unexpected nil")
            return
        }

        XCTAssertEqual(medTiming.currentItems.count, 1)
        XCTAssertEqual(medTiming.missedItems.count, 0)

        guard let medA3Item1 = medTiming.currentItems.first as? SBATrackedMedicationLoggingTableItem else {
            XCTFail("Failed to build expected medication.")
            return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timingIdentifier, timestamps.first!.uuid)
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNotNil(medA3Item1.loggedDate)
    }

    func testAvailableMeds_Morning_NoMedsTaken_Monday() {
        var medA4 = SBAMedicationAnswer(identifier: "medA4")
        let timestamps = ["07:30", "10:30"].map { SBATimestamp(timeOfDay: $0, loggedDate: nil) }
        let dose = SBADosage(dosage: "40 mg",
                             daysOfWeek: [.monday, .wednesday, .friday],
                             timestamps: timestamps,
                             isAnytime: false)
        medA4.dosageItems = [dose]

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 5)
        guard let medTiming = medA4.availableMedications(at: timeOfDay) else {
            XCTFail("Unexpected nil")
            return
        }

        XCTAssertEqual(medTiming.currentItems.count, 2)
        XCTAssertEqual(medTiming.missedItems.count, 0)
    }

    func testBuildSections_Morning_NoMedsTaken_Before1030() {

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 5)
        let result = buildMedicationResult(identifier: "review")
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 1)

        guard let firstSection = sections.first else {
            XCTFail("Sections weren't build.")
            return
        }

        XCTAssertEqual(firstSection.title, "Morning medications")
        XCTAssertEqual(firstSection.tableItems.count, 4)

        guard firstSection.tableItems.count >= 4,
            let medA3Item1 = firstSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA4Item1 = firstSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA4Item2 = firstSection.tableItems[2] as? SBATrackedLoggingTableItem,
            let medA5Item1 = firstSection.tableItems[3] as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNil(medA3Item1.loggedDate)

        XCTAssertEqual(medA4Item1.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item1.groupIndex, 0)
        XCTAssertEqual(medA4Item1.rowIndex, 1)
        XCTAssertEqual(medA4Item1.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item1.timeText, "7:30 AM")
        XCTAssertEqual(medA4Item1.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item1.loggedDate)

        XCTAssertEqual(medA4Item2.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item2.groupIndex, 1)
        XCTAssertEqual(medA4Item2.rowIndex, 2)
        XCTAssertEqual(medA4Item2.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item2.timeText, "10:30 AM")
        XCTAssertEqual(medA4Item2.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item2.loggedDate)

        XCTAssertEqual(medA5Item1.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item1.groupIndex, 0)
        XCTAssertEqual(medA5Item1.rowIndex, 3)
        XCTAssertEqual(medA5Item1.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item1.timeText)
        XCTAssertNil(medA5Item1.detail)
        XCTAssertNil(medA5Item1.loggedDate)

    }

    func testBuildSections_Morning_NoMedsTaken_After1030() {

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 40)
        let result = buildMedicationResult(identifier: "review")
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 1)

        guard let firstSection = sections.first else {
            XCTFail("Sections weren't build.")
            return
        }

        XCTAssertEqual(firstSection.title, "Morning medications")
        XCTAssertEqual(firstSection.tableItems.count, 4)

        guard firstSection.tableItems.count >= 4,
            let medA3Item1 = firstSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA4Item1 = firstSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA4Item2 = firstSection.tableItems[2] as? SBATrackedLoggingTableItem,
            let medA5Item1 = firstSection.tableItems[3] as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNil(medA3Item1.loggedDate)

        XCTAssertEqual(medA4Item1.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item1.groupIndex, 0)
        XCTAssertEqual(medA4Item1.rowIndex, 1)
        XCTAssertEqual(medA4Item1.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item1.timeText, "7:30 AM")
        XCTAssertEqual(medA4Item1.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item1.loggedDate)

        XCTAssertEqual(medA4Item2.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item2.groupIndex, 1)
        XCTAssertEqual(medA4Item2.rowIndex, 2)
        XCTAssertEqual(medA4Item2.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item2.timeText, "10:30 AM")
        XCTAssertEqual(medA4Item2.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item2.loggedDate)

        XCTAssertEqual(medA5Item1.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item1.groupIndex, 0)
        XCTAssertEqual(medA5Item1.rowIndex, 3)
        XCTAssertEqual(medA5Item1.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item1.timeText)
        XCTAssertNil(medA5Item1.detail)
        XCTAssertNil(medA5Item1.loggedDate)
    }

    func testBuildSections_Afternoon_NoMedsTaken() {

        let timeOfDay = buildDate(weekday: .monday, hour: 12, minute: 40)
        let result = buildMedicationResult(identifier: "review")
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 2)

        guard let firstSection = sections.first,
            let missedSection = sections.last else {
            XCTFail("Sections weren't build.")
            return
        }

        XCTAssertEqual(firstSection.title, "Afternoon medications")
        XCTAssertEqual(firstSection.tableItems.count, 2)

        guard let medA3Item0 = firstSection.tableItems.first as? SBATrackedLoggingTableItem,
            let medA5Item1 = firstSection.tableItems.last as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item0.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item0.groupIndex, 0)
        XCTAssertEqual(medA3Item0.rowIndex, 0)
        XCTAssertEqual(medA3Item0.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item0.timeText, "12:00 PM")
        XCTAssertEqual(medA3Item0.detail, "Every day")
        XCTAssertNil(medA3Item0.loggedDate)

        XCTAssertEqual(medA5Item1.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item1.groupIndex, 0)
        XCTAssertEqual(medA5Item1.rowIndex, 1)
        XCTAssertEqual(medA5Item1.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item1.timeText)
        XCTAssertNil(medA5Item1.detail)
        XCTAssertNil(medA5Item1.loggedDate)

        guard missedSection.tableItems.count == 3,
            let medA3Item1 = missedSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA4Item1 = missedSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA4Item2 = missedSection.tableItems[2] as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(missedSection)")
                return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNil(medA3Item1.loggedDate)

        XCTAssertEqual(medA4Item1.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item1.groupIndex, 0)
        XCTAssertEqual(medA4Item1.rowIndex, 1)
        XCTAssertEqual(medA4Item1.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item1.timeText, "7:30 AM")
        XCTAssertEqual(medA4Item1.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item1.loggedDate)

        XCTAssertEqual(medA4Item2.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item2.groupIndex, 1)
        XCTAssertEqual(medA4Item2.rowIndex, 2)
        XCTAssertEqual(medA4Item2.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item2.timeText, "10:30 AM")
        XCTAssertEqual(medA4Item2.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item2.loggedDate)
    }

    func testBuildSections_Evening_NoMedsTaken() {

        let timeOfDay = buildDate(weekday: .monday, hour: 20, minute: 40)
        let result = buildMedicationResult(identifier: "review")
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 2)

        guard let firstSection = sections.first,
            let missedSection = sections.last else {
                XCTFail("Sections weren't build.")
                return
        }

        XCTAssertEqual(firstSection.title, "Evening medications")
        XCTAssertEqual(firstSection.tableItems.count, 2)

        guard let medA3Item0 = firstSection.tableItems.first as? SBATrackedLoggingTableItem,
            let medA5Item1 = firstSection.tableItems.last as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item0.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item0.groupIndex, 0)
        XCTAssertEqual(medA3Item0.rowIndex, 0)
        XCTAssertEqual(medA3Item0.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item0.timeText, "8:00 PM")
        XCTAssertEqual(medA3Item0.detail, "Every day")
        XCTAssertNil(medA3Item0.loggedDate)

        XCTAssertEqual(medA5Item1.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item1.groupIndex, 0)
        XCTAssertEqual(medA5Item1.rowIndex, 1)
        XCTAssertEqual(medA5Item1.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item1.timeText)
        XCTAssertNil(medA5Item1.detail)
        XCTAssertNil(medA5Item1.loggedDate)

        guard missedSection.tableItems.count == 4,
            let medA3Item1 = missedSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA3Item2 = missedSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA4Item1 = missedSection.tableItems[2] as? SBATrackedLoggingTableItem,
            let medA4Item2 = missedSection.tableItems[3] as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(missedSection)")
                return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNil(medA3Item1.loggedDate)

        XCTAssertEqual(medA3Item2.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item2.groupIndex, 1)
        XCTAssertEqual(medA3Item2.rowIndex, 1)
        XCTAssertEqual(medA3Item2.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item2.timeText, "12:00 PM")
        XCTAssertEqual(medA3Item2.detail, "Every day")
        XCTAssertNil(medA3Item2.loggedDate)

        XCTAssertEqual(medA4Item1.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item1.groupIndex, 0)
        XCTAssertEqual(medA4Item1.rowIndex, 2)
        XCTAssertEqual(medA4Item1.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item1.timeText, "7:30 AM")
        XCTAssertEqual(medA4Item1.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item1.loggedDate)

        XCTAssertEqual(medA4Item2.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item2.groupIndex, 1)
        XCTAssertEqual(medA4Item2.rowIndex, 3)
        XCTAssertEqual(medA4Item2.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item2.timeText, "10:30 AM")
        XCTAssertEqual(medA4Item2.detail, "Mon, Wed, Fri")
        XCTAssertNil(medA4Item2.loggedDate)
    }

    func testBuildSections_Morning_AllMedsTaken() {

        let timeOfDay = buildDate(weekday: .monday, hour: 10, minute: 40)
        let result = buildMedicationResult(identifier: "review", medsTaken: buildMondayTimestamps(at: .morning))
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 1)

        guard let firstSection = sections.first else {
            XCTFail("Sections weren't build.")
            return
        }

        XCTAssertEqual(firstSection.title, "Morning medications")
        XCTAssertEqual(firstSection.tableItems.count, 5)

        guard firstSection.tableItems.count >= 5,
            let medA3Item1 = firstSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA4Item1 = firstSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA4Item2 = firstSection.tableItems[2] as? SBATrackedLoggingTableItem,
            let medA5Item0 = firstSection.tableItems[3] as? SBATrackedLoggingTableItem,
            let medA5ItemMorning = firstSection.tableItems[4] as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item1.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item1.groupIndex, 0)
        XCTAssertEqual(medA3Item1.rowIndex, 0)
        XCTAssertEqual(medA3Item1.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item1.timeText, "8:00 AM")
        XCTAssertEqual(medA3Item1.detail, "Every day")
        XCTAssertNotNil(medA3Item1.loggedDate)

        XCTAssertEqual(medA4Item1.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item1.groupIndex, 0)
        XCTAssertEqual(medA4Item1.rowIndex, 1)
        XCTAssertEqual(medA4Item1.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item1.timeText, "7:45 AM")
        XCTAssertEqual(medA4Item1.detail, "Mon, Wed, Fri")
        XCTAssertNotNil(medA4Item1.loggedDate)

        XCTAssertEqual(medA4Item2.title, "medA4 40 mg")
        XCTAssertEqual(medA4Item2.groupIndex, 1)
        XCTAssertEqual(medA4Item2.rowIndex, 2)
        XCTAssertEqual(medA4Item2.itemIdentifier, "medA4")
        XCTAssertEqual(medA4Item2.timeText, "10:30 AM")
        XCTAssertEqual(medA4Item2.detail, "Mon, Wed, Fri")
        XCTAssertNotNil(medA4Item2.loggedDate)
        
        XCTAssertEqual(medA5Item0.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item0.groupIndex, 0)
        XCTAssertEqual(medA5Item0.rowIndex, 3)
        XCTAssertEqual(medA5Item0.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item0.timeText)
        XCTAssertNil(medA5Item0.detail)
        XCTAssertNil(medA5Item0.loggedDate)

        XCTAssertEqual(medA5ItemMorning.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemMorning.groupIndex, 1)
        XCTAssertEqual(medA5ItemMorning.rowIndex, 4)
        XCTAssertEqual(medA5ItemMorning.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemMorning.timeText, "8:00 AM")
        XCTAssertNil(medA5ItemMorning.detail)
        XCTAssertNotNil(medA5ItemMorning.loggedDate)
    }

    func testBuildSections_Afternoon_AllMedsTaken() {

        let timeOfDay = buildDate(weekday: .monday, hour: 12, minute: 40)
        let result = buildMedicationResult(identifier: "review", medsTaken: buildMondayTimestamps(at: .afternoon))
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 1)

        guard let firstSection = sections.first else {
                XCTFail("Sections weren't build.")
                return
        }

        XCTAssertEqual(firstSection.title, "Afternoon medications")
        XCTAssertEqual(firstSection.tableItems.count, 4)

        guard firstSection.tableItems.count >= 4,
            let medA3Item0 = firstSection.tableItems[0] as? SBATrackedMedicationLoggingTableItem,
            let medA5Item0 = firstSection.tableItems[1] as? SBATrackedMedicationLoggingTableItem,
            let medA5ItemMorning = firstSection.tableItems[2] as? SBATrackedMedicationLoggingTableItem,
            let medA5ItemAfternoon = firstSection.tableItems[3] as? SBATrackedMedicationLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item0.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item0.groupIndex, 0)
        XCTAssertEqual(medA3Item0.rowIndex, 0)
        XCTAssertEqual(medA3Item0.groupCount, 1)
        XCTAssertEqual(medA3Item0.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item0.timeText, "12:15 PM")
        XCTAssertEqual(medA3Item0.detail, "Every day")
        XCTAssertNotNil(medA3Item0.loggedDate)
        
        XCTAssertEqual(medA5Item0.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item0.groupIndex, 0)
        XCTAssertEqual(medA5Item0.rowIndex, 1)
        XCTAssertEqual(medA5Item0.groupCount, 3)
        XCTAssertEqual(medA5Item0.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item0.timeText)
        XCTAssertNil(medA5Item0.detail)
        XCTAssertNil(medA5Item0.loggedDate)
        
        XCTAssertEqual(medA5ItemMorning.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemMorning.groupIndex, 1)
        XCTAssertEqual(medA5ItemMorning.rowIndex, 2)
        XCTAssertEqual(medA5ItemMorning.groupCount, 3)
        XCTAssertEqual(medA5ItemMorning.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemMorning.timeText, "8:00 AM")
        XCTAssertNil(medA5ItemMorning.detail)
        XCTAssertNotNil(medA5ItemMorning.loggedDate)

        XCTAssertEqual(medA5ItemAfternoon.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemAfternoon.groupIndex, 2)
        XCTAssertEqual(medA5ItemAfternoon.rowIndex, 3)
        XCTAssertEqual(medA5ItemAfternoon.groupCount, 3)
        XCTAssertEqual(medA5ItemAfternoon.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemAfternoon.timeText, "12:15 PM")
        XCTAssertNil(medA5ItemAfternoon.detail)
        XCTAssertNotNil(medA5ItemAfternoon.loggedDate)
    }

    func testBuildSections_Evening_AllMedsTaken() {

        let timeOfDay = buildDate(weekday: .monday, hour: 20, minute: 40)
        let result = buildMedicationResult(identifier: "review", medsTaken: buildMondayTimestamps(at: .evening))
        let meds = buildMedicationItems()
        let step = SBAMedicationLoggingStepObject(identifier: "logging", items: meds.items, sections: meds.sections, type: .logging)
        step.result = result

        let (sections, _) = SBAMedicationLoggingDataSource.buildLoggingSections(step: step, result: result, timeOfDay: timeOfDay)

        XCTAssertEqual(sections.count, 1)

        guard let firstSection = sections.first else {
                XCTFail("Sections weren't build.")
                return
        }

        XCTAssertEqual(firstSection.title, "Evening medications")
        XCTAssertEqual(firstSection.tableItems.count, 5)

        guard let medA3Item0 = firstSection.tableItems[0] as? SBATrackedLoggingTableItem,
            let medA5Item0 = firstSection.tableItems[1] as? SBATrackedLoggingTableItem,
            let medA5ItemMorning = firstSection.tableItems[2] as? SBATrackedLoggingTableItem,
            let medA5ItemAfternoon = firstSection.tableItems[3] as? SBATrackedLoggingTableItem,
            let medA5ItemEvening = firstSection.tableItems.last as? SBATrackedLoggingTableItem
            else {
                XCTFail("Table items weren't build. \(firstSection)")
                return
        }

        XCTAssertEqual(medA3Item0.title, "medA3 10 mg")
        XCTAssertEqual(medA3Item0.groupIndex, 0)
        XCTAssertEqual(medA3Item0.rowIndex, 0)
        XCTAssertEqual(medA3Item0.itemIdentifier, "medA3")
        XCTAssertEqual(medA3Item0.timeText, "8:45 PM")
        XCTAssertEqual(medA3Item0.detail, "Every day")
        XCTAssertNotNil(medA3Item0.loggedDate)
        
        XCTAssertEqual(medA5Item0.title, "medA5 5 ml")
        XCTAssertEqual(medA5Item0.groupIndex, 0)
        XCTAssertEqual(medA5Item0.rowIndex, 1)
        XCTAssertEqual(medA5Item0.itemIdentifier, "medA5")
        XCTAssertNil(medA5Item0.timeText)
        XCTAssertNil(medA5Item0.detail)
        XCTAssertNil(medA5Item0.loggedDate)
        
        XCTAssertEqual(medA5ItemMorning.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemMorning.groupIndex, 1)
        XCTAssertEqual(medA5ItemMorning.rowIndex, 2)
        XCTAssertEqual(medA5ItemMorning.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemMorning.timeText, "8:00 AM")
        XCTAssertNil(medA5ItemMorning.detail)
        XCTAssertNotNil(medA5ItemMorning.loggedDate)
        
        XCTAssertEqual(medA5ItemAfternoon.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemAfternoon.groupIndex, 2)
        XCTAssertEqual(medA5ItemAfternoon.rowIndex, 3)
        XCTAssertEqual(medA5ItemAfternoon.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemAfternoon.timeText, "12:15 PM")
        XCTAssertNil(medA5ItemAfternoon.detail)
        XCTAssertNotNil(medA5ItemAfternoon.loggedDate)

        XCTAssertEqual(medA5ItemEvening.title, "medA5 5 ml")
        XCTAssertEqual(medA5ItemEvening.groupIndex, 3)
        XCTAssertEqual(medA5ItemEvening.rowIndex, 4)
        XCTAssertEqual(medA5ItemEvening.itemIdentifier, "medA5")
        XCTAssertEqual(medA5ItemEvening.timeText, "8:45 PM")
        XCTAssertNil(medA5ItemEvening.detail)
        XCTAssertNotNil(medA5ItemEvening.loggedDate)
    }


    // Helper methods

    func buildDate(weekday: RSDWeekday, hour: Int, minute: Int) -> Date {

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: .gregorian)
        dateComponents.year = 2018
        dateComponents.month = 2
        dateComponents.weekdayOrdinal = 1
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.weekday = weekday.rawValue

        return dateComponents.date!
    }

    func buildMondayTimestamps(at timeRange: SBATimeRange) -> [String : [SBATimestamp]] {
        
        var medA3 = [
            SBATimestamp(timeOfDay: "08:00",
                                  loggedDate: self.buildDate(weekday: .sunday, hour: 8, minute: 0))
        ]
        
        let medA4 = [
            SBATimestamp(timeOfDay: "07:30", loggedDate: self.buildDate(weekday: .sunday, hour: 7, minute: 45)),
            SBATimestamp(timeOfDay: "10:30", loggedDate: self.buildDate(weekday: .sunday, hour: 10, minute: 30))
        ]
        
        var medA5 = [
            SBATimestamp(timeOfDay: nil, loggedDate: self.buildDate(weekday: .sunday, hour: 8, minute: 0))
        ]
        
        if timeRange >= .afternoon {
            medA3.append(SBATimestamp(timeOfDay: "12:00", loggedDate: self.buildDate(weekday: .sunday, hour: 12, minute: 15)))
            medA5.append(SBATimestamp(timeOfDay: nil, loggedDate: self.buildDate(weekday: .sunday, hour: 12, minute: 15)))
        }
        if timeRange >= .evening {
            medA3.append(SBATimestamp(timeOfDay: "20:00", loggedDate: self.buildDate(weekday: .sunday, hour: 20, minute: 45)))
            medA5.append(SBATimestamp(timeOfDay: nil, loggedDate: self.buildDate(weekday: .sunday, hour: 20, minute: 45)))
        }
        
        return [
            "medA3" : medA3,
            "medA4" : medA4,
            "medA5" : medA5,
        ]
    }

    func buildMedicationResult(identifier: String, medsTaken: [String : [SBATimestamp]] = [:]) -> SBAMedicationTrackingResult {

        func buildTimestamps(for medication:SBAMedicationAnswer, with times: [String]?) -> [SBATimestamp]? {
            guard let times = times else {
                return medsTaken[medication.identifier]?.filter { $0.timeOfDay == nil }
            }
            let inputs = medsTaken[medication.identifier]?.reduce(into: [String : SBATimestamp]()) { (hashtable, value) in
                guard let time = value.timeOfDay else { return }
                hashtable[time] = value
            }
            return times.compactMap { inputs?[$0] ?? SBATimestamp(timeOfDay: $0, loggedDate: nil) }
        }
        
        func buildDose(for medication:SBAMedicationAnswer, dosage: String, daysOfWeek: Set<RSDWeekday>? = nil, times: [String]? = nil) -> SBADosage {
            return SBADosage(dosage: dosage,
                             daysOfWeek: daysOfWeek,
                             timestamps: buildTimestamps(for: medication, with: times),
                             isAnytime: (daysOfWeek == nil))
        }
        
        var medA3 = SBAMedicationAnswer(identifier: "medA3")
        medA3.dosageItems = [buildDose(for: medA3,
                                       dosage: "10 mg",
                                       daysOfWeek: RSDWeekday.all,
                                       times: ["08:00", "12:00", "20:00"])]

        var medA4 = SBAMedicationAnswer(identifier: "medA4")
        medA4.dosageItems = [buildDose(for: medA4,
                                       dosage: "40 mg",
                                       daysOfWeek: [.monday, .wednesday, .friday],
                                       times: ["07:30", "10:30"])]

        var medA5 = SBAMedicationAnswer(identifier: "medA5")
        medA5.dosageItems = [buildDose(for: medA5,
                                       dosage: "5 ml")]
 
        var medC3 = SBAMedicationAnswer(identifier: "medC3")
        medC3.dosageItems = [buildDose(for: medC3,
                                       dosage: "2 ml",
                                       daysOfWeek: [.sunday, .thursday],
                                       times: ["08:00", "20:00"])]
        
        var result = SBAMedicationTrackingResult(identifier: identifier)
        result.medications = [medA3, medA4, medA5, medC3]

        return result
    }
}
