// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func cleansMikesSMB3() {
    #expect(NameCleaner.clean("Super Mario Bros 3 (U) (PRG 1) [h2]", headerTitle: nil) == "Super Mario Bros 3 (USA) (PRG 1) [Hack]")
}
@Test func translationsAndVerifiedFlag() {
    #expect(NameCleaner.clean("Zelda_no_Densetsu (J) [T+Eng1.0_Translator] [!]", headerTitle: nil)
        == "Zelda no Densetsu (Japan) [Translation Eng]")
}
@Test func multiRegionAndBadDump() {
    #expect(NameCleaner.clean("Sonic (UE) [b1]", headerTitle: nil) == "Sonic (USA, Europe) [Bad Dump]")
}
@Test func uninformativeNamesUseHeaderTitle() {
    #expect(NameCleaner.clean("disc", headerTitle: "FINAL FANTASY VII") == "Final Fantasy Vii")
    #expect(NameCleaner.clean("SLUS_200.62", headerTitle: "GRAN TURISMO") == "Gran Turismo")
    #expect(NameCleaner.clean("game1 (U)", headerTitle: "METROID") == "Metroid (USA)")
    #expect(NameCleaner.clean("disc", headerTitle: nil) == "disc")
}
@Test func alreadyCleanIsUnchanged() {
    #expect(NameCleaner.clean("Already Clean (USA)", headerTitle: "OTHER") == "Already Clean (USA)")
    #expect(NameCleaner.clean("Game Name [0100ABCD00010000][v0]", headerTitle: nil) == "Game Name")
}
