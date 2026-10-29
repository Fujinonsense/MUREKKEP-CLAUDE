package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Test

// The mesh plan cases of tools/swiftcheck/main.swift ("Ink meshes"), with the same strokes.
class InkMeshPlanTest {
    private fun strokes(ids: List<Int>, highlighter: Set<Int> = emptySet(), grass: Set<Int> = emptySet()) =
        ids.map { InkMeshPlan.Entry(it, it in highlighter, it in grass) }

    @Test
    fun sameStrokesKeepTheBuffers() {
        assertEquals(InkMeshPlan.Same, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 5, 6))))
    }

    @Test
    fun newPenStrokesAreAppended() {
        assertEquals(InkMeshPlan.Append(3), InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 5, 6, 9, 10))))
    }

    @Test
    fun bufferOrderPutsHighlightersFirst() {
        assertEquals(InkMeshPlan.Append(3), InkMeshPlan.plan(listOf(2, 4, 5), strokes(listOf(4, 2, 5, 9), highlighter = setOf(2))))
    }

    @Test
    fun aNewHighlighterGoesAmongTheHighlightersTheMeshesStay() {
        assertEquals(InkMeshPlan.Keep, InkMeshPlan.plan(listOf(4, 5), strokes(listOf(4, 5, 9), highlighter = setOf(9))))
    }

    @Test
    fun newGrassRebuilds() {
        assertEquals(InkMeshPlan.Rebuild, InkMeshPlan.plan(listOf(4, 5), strokes(listOf(4, 5, 9), grass = setOf(9))))
    }

    @Test
    fun anErasedStrokeKeepsTheOthersMeshes() {
        assertEquals(InkMeshPlan.Keep, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 6))))
    }

    @Test
    fun anErasedAndANewStrokeKeepTheMeshes() {
        assertEquals(InkMeshPlan.Keep, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 6, 9))))
    }

    @Test
    fun aCutStrokesPiecesInItsPlace() {
        assertEquals(InkMeshPlan.Keep, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 7, 8, 6))))
    }

    @Test
    fun aReorderedPageKeepsTheMeshes() {
        assertEquals(InkMeshPlan.Keep, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(5, 4, 6))))
    }

    @Test
    fun grassAmongTheOthersRebuilds() {
        assertEquals(InkMeshPlan.Rebuild, InkMeshPlan.plan(listOf(4, 5, 6), strokes(listOf(4, 9, 6), grass = setOf(9))))
    }

    @Test
    fun anEmptyPageIsBuilt() {
        assertEquals(InkMeshPlan.Rebuild, InkMeshPlan.plan(emptyList(), strokes(listOf(1, 2))))
    }
}
