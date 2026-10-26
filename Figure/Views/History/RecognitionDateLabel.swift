import SwiftUI

struct RecognitionDateLabel: View {
    let date: Date

    var body: some View {
        if Calendar.current.isDateInToday(date) {
            Text("Сьогодні, \(date.formatted(date: .omitted, time: .shortened))")
        } else {
            Text(date, format: .dateTime.day().month().hour().minute())
        }
    }
}

