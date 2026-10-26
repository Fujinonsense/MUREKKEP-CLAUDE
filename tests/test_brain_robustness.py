"""The on-device AI and Studio hold up on an iPad (version 1.1, from the 2026-10-26 audit): the
background stops the GPU model but not the job, the free plan pays only for what gets made, questions
asked inside an overview go to the downloaded model, a script's language is checked scene by scene,
and on an 8 GB iPad the model and the PDF pages share the memory. The gate and the language check
themselves run in tools/braincheck; this checks the wiring in the app's source."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_the_background_stops_the_model_but_not_the_job():
    gate = src("BrainGate.swift")
    assert "struct BrainInterrupted: LocalizedError" in gate
    assert "throw BrainInterrupted(started: false)" in gate  # may not start while the app is away
    assert "Thread.sleep(forTimeInterval: 0.01)" in gate and "usleep" not in gate
    runtime = src("BrainRuntime.swift")
    assert "throw BrainInterrupted(started: true)" in runtime  # stopped in the middle
    assert "final class BrainGate" not in runtime
    # The writers hand the interruption up instead of swallowing it into a lesser writer.
    for name in ("StudioWriter.swift", "StudyWriter.swift"):
        assert re.search(r"catch let interrupted as BrainInterrupted \{\s*(//[^\n]*\n\s*)*throw interrupted", src(name)), name
    # The job keeps the step, waits for the screen and starts it again with the same writer.
    work = src("BackgroundWork.swift")
    assert "beginBackgroundTask(withName: name)" in work and "endBackgroundTask(id)" in work
    assert "catch is BrainInterrupted" in work and "await waitUntilActive()" in work
    assert "UIApplication.didBecomeActiveNotification" in work and "applicationState != .active" in work
    assert 'Loc.t("Uygulama arka plana geçince durdu; geri dönünce yeniden başlar.")' in work
    for name, label in (("Studio.swift", "studio"), ("StudyStore.swift", "study")):
        text = src(name)
        assert f'BackgroundWork("{label}")' in text and "defer { background.end() }" in text, name
        assert "BackgroundWork.retrying(paused: { job.phase = $0 })" in text, name


def test_a_job_pays_only_when_it_is_made():
    store = src("ProStore.swift")
    refund = store[store.index("func refund(_ feature: ProPlan.Feature, count: Int = 1)"):]
    assert "guard Self.sells, !isPro, count > 0 else { return }" in refund[:200]
    assert "max(0, used - count)" in refund[:600]
    for name, feature in (("Studio.swift", ".overview"), ("StudyStore.swift", ".studySet")):
        text = src(name)
        start = text[text.index("func start(options:"):]
        assert f"defer {{ if !made {{ ProStore.shared.refund({feature}) }} }}" in start, name
        assert start.count("made = true") >= 1, name
        assert start.index("defer { if !made") < start.index("if Task.isCancelled"), name  # a queued job cancelled pays nothing
        # A failed job can be started again; that try counts again.
        assert f"guard let self, ProStore.shared.use({feature}) else {{ return }}" in start, name
        assert "job.retry = { [weak self] in" in start, name
    # The silent save (no voices in the build) is still a made overview.
    studio = src("Studio.swift")
    assert re.search(r"self\.save\(overview\)\s*made = true\s*job\.phase = Loc\.t\(\"Sessiz kaydedildi\"\)", studio)
    for name in ("StudioViews.swift", "StudyViews.swift"):
        assert 'Button(Loc.t("Tekrar dene"), action: retry)' in src(name), name
    # The sheets still count up front, so the Pro page opens before the work starts.
    assert "ProStore.shared.use(.overview, count: max(1, picked.count))" in src("StudioViews.swift")
    assert "ProStore.shared.use(.studySet)" in src("StudyViews.swift")


def test_questions_inside_an_overview_go_to_the_downloaded_model():
    player = src("OverviewPlayer.swift")
    answer = player[player.index("enum OverviewQuestions"):player.index("// MARK: - Thumbnails")]
    assert "let brainReady = DeviceBrain.shared.isReady" in answer
    assert "!(brainReady || OnDeviceAI.isAvailable)" in answer  # Claude first only when the iPad has no model
    assert answer.index("BrainRuntime.complete(request, directory: directory)") < answer.index("OnDeviceAI.respond(")
    assert "ThinkingText.split(raw, thinking: false).answer" in answer


def test_a_script_is_checked_scene_by_scene():
    writer = src("StudioWriter.swift")
    assert 'speaks(language, overview.segmentTexts.joined(separator: " "))' not in writer
    brain = writer[writer.index("private static func brain("):writer.index("// MARK: On the device")]
    assert "ScriptLanguage.wrong(texts) { speaks(language, $0) }" in brain
    assert "ScriptLanguage.keeps(total: texts.count, wrong: wrong.count)" in brain
    assert "ScriptLanguage.rewritten(" in brain and "overview.setSegmentText(i, text)" in brain
    assert "overview.removeSegments(dropped)" in brain
    language = src("ScriptLanguage.swift")
    assert "total > 0 && wrong * 2 < total" in language
    studio = src("Studio.swift")
    assert "mutating func setSegmentText(_ i: Int, _ text: String)" in studio
    assert "mutating func removeSegments(_ indices: Set<Int>)" in studio


def test_the_model_and_the_pages_share_the_memory():
    runtime = src("BrainRuntime.swift")
    assert "static let idleLimit: TimeInterval = 180" in runtime
    host = runtime[runtime.index("private actor BrainHost"):]
    release = host[host.index("func release()"):host.index("func warm(")]
    assert "scheduleIdleUnload()" in release
    assert re.search(r"func unloadAfterIdle\(\) \{\s*guard !busy, Date\(\)\.timeIntervalSince\(lastUse\) >= Self\.idleLimit - 1", host)
    load = host[host.index("private func load("):host.index("func generate(")]
    # Every load asks the pages for room first, not only when memory is already short.
    assert load.index("NotificationCenter.default.post(name: BrainRuntime.needsMemory") < load.index("if free > 0, free < need")
    pdf = src("PDFSupport.swift")
    assert "UIApplication.didReceiveMemoryWarningNotification, BrainRuntime.needsMemory" in pdf
    assert re.search(r"func purgeForMemory\(\) \{[^}]*purge\(keeping: keep\)", pdf, re.S)
    assert "NotificationCenter.default.removeObserver(observer)" in pdf
    assert "Task { await BrainRuntime.unloadIfIdle() }" in src("DeviceBrain.swift")
