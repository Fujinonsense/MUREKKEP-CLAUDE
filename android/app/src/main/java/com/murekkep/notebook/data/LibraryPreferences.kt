package com.murekkep.notebook.data

import android.content.Context
import android.content.SharedPreferences
import com.murekkep.notebook.ui.CourseTab
import com.murekkep.notebook.ui.LibraryFilter
import com.murekkep.notebook.ui.LibraryPlace
import com.murekkep.notebook.ui.LibrarySort

// Where the library was left (the iPad's @AppStorage library.place, library.filter, library.sort
// and course.tab): the list or the course, the filter of Tüm notlar, the order and a course's tab
// come back after a relaunch.

class LibraryPreferences(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("library", Context.MODE_PRIVATE)

    var place: LibraryPlace
        get() = LibraryPlace.fromRaw(prefs.getString("library.place", null))
        set(value) = prefs.edit().putString("library.place", value.raw).apply()

    var filter: LibraryFilter
        get() = LibraryFilter.fromRaw(prefs.getString("library.filter", null))
        set(value) = prefs.edit().putString("library.filter", value.raw).apply()

    var sort: LibrarySort
        get() = LibrarySort.fromRaw(prefs.getString("library.sort", null))
        set(value) = prefs.edit().putString("library.sort", value.raw).apply()

    var courseTab: CourseTab
        get() = CourseTab.fromRaw(prefs.getString("course.tab", null))
        set(value) = prefs.edit().putString("course.tab", value.raw).apply()
}
