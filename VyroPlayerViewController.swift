import UIKit
import AVFoundation
import AVKit
import MobileVLCKit

final class VyroPlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    var onProgress: ((Double, Double) -> Void)?
    var onClose: ((Double, Double, Bool, Bool) -> Void)?

    private let url: URL
    private let titleText: String
    private let startSec: Double
    private let hasNext: Bool

    private let player = VLCMediaPlayer()
    private let videoView = UIView()
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel = UILabel()
    private let curLabel = UILabel()
    private let durLabel = UILabel()
    private let slider = UISlider()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let toast = UILabel()
    private let playBtn = UIButton(type: .system)
    private let speedBtn = UIButton(type: .system)

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
    private var rateIdx = 1
    private var timer: Timer?
    private var hideTimer: Timer?
    private var scrubbing = false
    private var resumed = false
    private var everPlayed = false
    private var ended = false
    private var closed = false
    private var failed = false
    private var fitted = false
    private var controlsVisible = true
    private let aspects = ["Fit", "Fill", "16:9", "4:3"]
    private var aspectIdx = 0
    private var panStartValue: CGFloat = 0
    private var panIsVolume = false
    private var volume: Int32 = 100
    private var lastCur = 0.0
    private var lastLen = 0.0
    private var lastReport = Date.distantPast
    private let openedAt = Date()

    init(url: URL, title: String, start: Double, hasNext: Bool) {
        self.url = url
        self.titleText = title
        self.startSec = start
        self.hasNext = hasNext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        buildUI()

        player.drawable = videoView
        player.media = VLCMedia(url: url)
        player.play()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        scheduleHide()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // Keep the picture fitted inside the screen (no zoom / crop).
    private func fitVideo() {
        let sel = Selector(("setScaleFactor:"))
        if player.responds(to: sel) { player.setValue(Float(0), forKey: "scaleFactor") }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fitVideo()
    }

    // MARK: UI

    private func buildUI() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.backgroundColor = .black
        videoView.contentMode = .scaleAspectFit
        videoView.clipsToBounds = true
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let single = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        for g in [single, double, pan] as [UIGestureRecognizer] { g.delegate = self; view.addGestureRecognizer(g) }

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()

        // Top bar
        let close = iconButton("xmark", #selector(closeTapped))
        titleLabel.text = titleText
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        let aspectBtn = iconButton("aspectratio", #selector(aspectTapped))
        let route = AVRoutePickerView()
        route.tintColor = .white
        route.activeTintColor = .white
        route.widthAnchor.constraint(equalToConstant: 44).isActive = true
        route.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let topStack = UIStackView(arrangedSubviews: [close, titleLabel, aspectBtn, route])
        topStack.axis = .horizontal
        topStack.spacing = 6
        topStack.alignment = .center
        style(bar: topBar, radius: 26)
        embed(topStack, in: topBar, inset: 8)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])

        // Bottom bar
        for l in [curLabel, durLabel] {
            l.textColor = .white
            l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            l.text = "0:00"
            l.setContentHuggingPriority(.required, for: .horizontal)
            l.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        durLabel.text = "--:--"
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.addTarget(self, action: #selector(scrubStart), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubMove), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnd), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let timeRow = UIStackView(arrangedSubviews: [curLabel, slider, durLabel])
        timeRow.axis = .horizontal
        timeRow.spacing = 10
        timeRow.alignment = .center

        playBtn.tintColor = .white
        playBtn.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playBtn.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        speedBtn.tintColor = .white
        speedBtn.setTitle("1×", for: .normal)
        speedBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        speedBtn.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)

        var buttons: [UIView] = [
            iconButton("speaker.wave.2.fill", #selector(audioTapped)),
            iconButton("captions.bubble.fill", #selector(subsTapped)),
            iconButton("gobackward.10", #selector(backTapped)),
            playBtn,
            iconButton("goforward.10", #selector(fwdTapped)),
            speedBtn
        ]
        if hasNext { buttons.append(iconButton("forward.end.fill", #selector(nextTapped))) }
        let btnRow = UIStackView(arrangedSubviews: buttons)
        btnRow.axis = .horizontal
        btnRow.distribution = .fillEqually
        btnRow.alignment = .center
        for b in buttons { b.heightAnchor.constraint(equalToConstant: 44).isActive = true }

        let col = UIStackView(arrangedSubviews: [timeRow, btnRow])
        col.axis = .vertical
        col.spacing = 4
        style(bar: bottomBar, radius: 26)
        embed(col, in: bottomBar, inset: 14)
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])

        // Toast
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14, weight: .bold)
        toast.textAlignment = .center
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14),
            toast.heightAnchor.constraint(equalToConstant: 34),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
    }

    private func style(bar: UIVisualEffectView, radius: CGFloat) {
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = radius
        bar.layer.borderWidth = 1
        bar.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        bar.clipsToBounds = true
        view.addSubview(bar)
    }

    private func embed(_ inner: UIView, in bar: UIVisualEffectView, inset: CGFloat) {
        inner.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: bar.contentView.topAnchor, constant: inset),
            inner.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor, constant: -inset),
            inner.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: inset),
            inner.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -inset)
        ])
    }

    private func iconButton(_ symbol: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.tintColor = .white
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return b
    }

    private func flash(_ text: String) {
        toast.text = "  \(text)  "
        UIView.animate(withDuration: 0.2) { self.toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 1.8, options: []) { self.toast.alpha = 0 }
    }

    private func setControls(_ show: Bool) {
        controlsVisible = show
        UIView.animate(withDuration: 0.25) {
            self.topBar.alpha = show ? 1 : 0
            self.bottomBar.alpha = show ? 1 : 0
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self = self, self.player.isPlaying, !self.scrubbing else { return }
            self.setControls(false)
        }
    }

    // MARK: Actions

    @objc private func toggleControls() {
        setControls(!controlsVisible)
        if controlsVisible { scheduleHide() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let v = touch.view else { return true }
        return !(v.isDescendant(of: topBar) || v.isDescendant(of: bottomBar))
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        let x = g.location(in: view).x
        if x < view.bounds.midX { player.jumpBackward(10); flash("−10s") }
        else { player.jumpForward(10); flash("+10s") }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let h = max(view.bounds.height, 1)
        switch g.state {
        case .began:
            panIsVolume = g.location(in: view).x > view.bounds.midX
            panStartValue = panIsVolume ? CGFloat(volume) : UIScreen.main.brightness
        case .changed:
            let delta = -g.translation(in: view).y / (h * 0.6)
            if panIsVolume {
                let v = min(max(panStartValue + delta * 200, 0), 200)
                volume = Int32(v)
                player.audio.volume = volume
                flash("Volume \(Int(v / 2))%")
            } else {
                let b = min(max(panStartValue + delta, 0.02), 1)
                UIScreen.main.brightness = b
                flash("Brightness \(Int(b * 100))%")
            }
        default: break
        }
    }

    @objc private func aspectTapped() {
        aspectIdx = (aspectIdx + 1) % aspects.count
        applyAspect()
        flash(aspects[aspectIdx])
        scheduleHide()
    }

    private func applyAspect() {
        player.videoAspectRatio = nil
        player.videoCropGeometry = nil
        switch aspects[aspectIdx] {
        case "Fill":
            let w = Int(view.bounds.width), h = Int(view.bounds.height)
            player.videoCropGeometry = UnsafeMutablePointer<Int8>(mutating: ("\(w):\(h)" as NSString).utf8String)
        case "16:9":
            player.videoAspectRatio = UnsafeMutablePointer<Int8>(mutating: ("16:9" as NSString).utf8String)
        case "4:3":
            player.videoAspectRatio = UnsafeMutablePointer<Int8>(mutating: ("4:3" as NSString).utf8String)
        default: break
        }
    }

    @objc private func closeTapped() { finish(next: false) }
    @objc private func nextTapped() { finish(next: true) }

    @objc private func playTapped() {
        if player.isPlaying { player.pause() } else { player.play() }
        scheduleHide()
    }

    @objc private func backTapped() { player.jumpBackward(10); scheduleHide() }
    @objc private func fwdTapped() { player.jumpForward(10); scheduleHide() }

    @objc private func speedTapped() {
        rateIdx = (rateIdx + 1) % rates.count
        player.rate = rates[rateIdx]
        let r = rates[rateIdx]
        speedBtn.setTitle(r == r.rounded() ? "\(Int(r))×" : "\(r)×", for: .normal)
        scheduleHide()
    }

    @objc private func scrubStart() { scrubbing = true; hideTimer?.invalidate() }
    @objc private func scrubMove() { curLabel.text = fmt(Double(slider.value) * lastLen) }
    @objc private func scrubEnd() {
        player.position = slider.value
        scrubbing = false
        scheduleHide()
    }

    @objc private func audioTapped() {
        pickTrack("Audio", names: player.audioTrackNames, indexes: player.audioTrackIndexes,
                  current: player.currentAudioTrackIndex, minCount: 2) { [weak self] i in
            self?.player.currentAudioTrackIndex = i
        }
    }

    @objc private func subsTapped() {
        pickTrack("Subtitles", names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes,
                  current: player.currentVideoSubTitleIndex, minCount: 2) { [weak self] i in
            self?.player.currentVideoSubTitleIndex = i
        }
    }

    private func pickTrack(_ title: String, names: [Any]?, indexes: [Any]?, current: Int32,
                           minCount: Int, set: @escaping (Int32) -> Void) {
        let n = (names as? [String]) ?? []
        let ix = (indexes as? [NSNumber]) ?? []
        guard n.count >= minCount, n.count == ix.count else {
            flash("No \(title.lowercased()) options in this file")
            return
        }
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (i, name) in n.enumerated() {
            let id = ix[i].int32Value
            sheet.addAction(UIAlertAction(title: (id == current ? "✓ " : "") + name, style: .default) { _ in set(id) })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        }
        present(sheet, animated: true)
        hideTimer?.invalidate()
    }

    // MARK: Playback loop

    private func ms(_ t: VLCTime?) -> Double {
        return ((t?.value) as NSNumber?)?.doubleValue ?? 0
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func tick() {
        if closed { return }
        let len = ms(player.media?.length) / 1000
        let cur = ms(player.time) / 1000
        if len > 0 { lastLen = len }
        if cur > 0 { lastCur = cur }

        if player.isPlaying { everPlayed = true; if !fitted { fitted = true; fitVideo() } }

        if !resumed {
            if startSec <= 1 {
                resumed = true
            } else if player.isPlaying && len > 0 {
                if startSec < len - 30 { player.position = Float(startSec / len) }
                resumed = true
            }
        }

        playBtn.setImage(UIImage(systemName: player.isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        durLabel.text = len > 0 ? fmt(len) : "--:--"
        if !scrubbing {
            curLabel.text = fmt(cur)
            slider.value = player.position
        }

        if Date().timeIntervalSince(lastReport) > 5, lastLen > 0, player.isPlaying {
            lastReport = Date()
            onProgress?(lastCur, lastLen)
        }

        switch player.state {
        case .ended:
            ended = true
            finish(next: hasNext)
        case .error:
            showError()
        case .opening, .buffering:
            if !everPlayed || !player.isPlaying { spinner.startAnimating() }
        default:
            spinner.stopAnimating()
        }
        if player.isPlaying { spinner.stopAnimating() }

        if !everPlayed && Date().timeIntervalSince(openedAt) > 45 { showError() }
    }

    private func showError() {
        if failed || closed { return }
        failed = true
        spinner.stopAnimating()
        let a = UIAlertController(title: "Can’t play this file",
                                  message: "VLC couldn’t open this stream. Check the link, your connection and your playlist details.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in self?.finish(next: false) })
        present(a, animated: true)
    }

    private func finish(next: Bool) {
        if closed { return }
        closed = true
        timer?.invalidate()
        hideTimer?.invalidate()
        let d = lastLen
        let t = ended ? lastLen : lastCur
        let didEnd = ended
        player.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        let cb = onClose
        let dismissAction = { [weak self] in
            self?.dismiss(animated: true) { cb?(t, d, didEnd, next) }
        }
        if presentedViewController != nil {
            presentedViewController?.dismiss(animated: false) { dismissAction() }
        } else {
            dismissAction()
        }
    }
}
