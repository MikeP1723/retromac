// SPDX-License-Identifier: GPL-3.0-or-later

/// Button indices reported by RetroArch's mfi joypad driver, named by physical position.
public enum MFiButton: Int, Sendable {
    case south = 0, west = 1, select = 2, start = 3
    case up = 4, down = 5, left = 6, right = 7
    case east = 8, north = 9
    case l1 = 10, r1 = 11, l2 = 12, r2 = 13, l3 = 14, r3 = 15
}
