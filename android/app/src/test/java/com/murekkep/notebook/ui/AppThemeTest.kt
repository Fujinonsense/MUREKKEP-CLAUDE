package com.murekkep.notebook.ui

import org.junit.Assert.assertEquals
import org.junit.Test

// Which look the library takes (LibraryBackdrop on iPad): a picture's own, else the system's. The
// rest of the app always takes the system's.
class AppThemeTest {
    @Test
    fun onlyAPictureSetsTheLibrarysLook() {
        // Black and white and the ruled paper follow the system.
        assertEquals(true, AppTheme.BLACK_WHITE.libraryDark(systemDark = true))
        assertEquals(false, AppTheme.BLACK_WHITE.libraryDark(systemDark = false))
        assertEquals(true, AppTheme.RULED.libraryDark(systemDark = true))
        assertEquals(false, AppTheme.RULED.libraryDark(systemDark = false))
        // While Pro is open a dark picture is dark by day and a light one light at night; a locked
        // theme shows as black and white and follows the system.
        assertEquals(Pro.UNLOCKED, AppTheme.EBRU.libraryDark(systemDark = false))
        assertEquals(!Pro.UNLOCKED, AppTheme.HOKKA.libraryDark(systemDark = true))
    }
}
