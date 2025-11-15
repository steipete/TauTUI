Below is a practical, no‑nonsense guide to Swift 6.2’s *approachable concurrency*: what changed, how to enable it, and how to use it without tripping over yourself.

---

## TL;DR

* **Single‑threaded by default (if you choose):** New build settings let you run your target on the **MainActor by default**, so most code is serialized unless you opt in to parallelism. Great for UI targets. ([Swift.org][1])
* **Opt‑in parallelism:** Use the new **`@concurrent`** attribute to explicitly hop off the current actor (e.g., the main actor) for work that should run on the concurrent thread pool. ([Swift.org][1])
* **More intuitive async semantics (feature flag):** There’s an **upcoming feature** that makes **`nonisolated async` functions inherit the caller’s actor**; that lowers boilerplate and surprises when you call async APIs from UI code. Migration tooling in 6.2 helps you adopt it. ([Swift.org][1])
* **Strict checks you can actually adopt:** Turn on **Complete** concurrency checking to find data races, module‑by‑module. ([Swift.org][2])
* **SPM support:** For packages, set **`.defaultIsolation(MainActor.self)`** per target to get the same “single‑threaded by default” feel. ([Apple Developer][3])

---

## 0) Switch the model on (safely)

**For Xcode targets (app/UI):**

* In Build Settings, set **Default Actor Isolation = MainActor**. New projects often start this way already; older ones need opting in. ([Apple Developer][4])

**For Swift Package targets:**

```swift
// Package.swift (tools-version: 6.2)
.target(
  name: "AppUI",
  swiftSettings: [
    .defaultIsolation(MainActor.self)   // SwiftPM 6.2+
  ]
)
```

This mirrors the Xcode setting at the package/target level. By default, packages remain **nonisolated** unless you set it. ([Apple Developer][3])

**Turn on strict checks (gradually):**

* Xcode: **Strict Concurrency Checking = Complete**, or in configs:
  `SWIFT_STRICT_CONCURRENCY = complete`
* SwiftPM (temporary): `swift build -Xswiftc -strict-concurrency=complete`
  Do it module‑by‑module to keep things moving. ([Swift.org][2])

**(Optional) Upcoming feature for clearer async semantics:**

* Enable the migration tooling / upcoming feature that makes **`nonisolated async` inherit the caller’s actor**. Xcode 26 / Swift 6.2 has guidance and fix‑its for this. Use it once you understand the impact. ([Swift.org][1])

---

## 1) New mental model

* **“Single‑threaded unless requested”:** With default isolation = **MainActor**, unannotated code is treated as main‑actor isolated. No more littering code with `@MainActor` just to make the compiler happy. ([Swift.org][1])
* **Async ≠ “background”:** `async` functions on the main actor still run on the main actor until a suspension point; they *don’t* block the actor while awaiting. Use **`@concurrent`** to *explicitly* offload heavy work. ([Swift.org][1])
* **`@concurrent` as your “parallelism switch”:** Put it on functions that should run on the concurrent pool so you keep the main actor free. This removes the need for ad‑hoc `Task.detached {}` in most cases. ([Swift.org][1])
* **(When enabled) `nonisolated async` inherits the caller’s actor:** Fewer surprising hops to a generic executor when you call methods from main‑actor contexts. ([Swift.org][1])

---

## 2) Day‑to‑day patterns

### A. UI first, heavy work explicit

```swift
// Target has Default Actor Isolation = MainActor
struct ProfileViewModel {
  // implicitly main-actor isolated members

  func loadProfile() async throws -> Profile {
    // Safe to kick off network on await; doesn’t block the actor
    let data = try await fetchProfileData()        // stays on main actor until await hits
    // Heavy parsing off the actor:
    let profile = try await parseProfile(data)     // see @concurrent below
    return profile
  }

  @concurrent
  func parseProfile(_ data: Data) async throws -> Profile {
    // Runs on the concurrent pool; OK to do CPU work here
    try await decodeProfile(data)
  }
}
```

* **Why**: keep behavior predictable (UI on main actor), and **opt in** to parallelism exactly where you need it via `@concurrent`. ([Swift.org][1])

### B. Networking helpers

```swift
enum API {
  @concurrent
  static func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(T.self, from: data)
  }
}
```

* Simple rule: network + decoding often belong off the actor; `@concurrent` makes that intent explicit. ([Swift.org][1])

### C. Batching work: `async let` vs. task groups

* **`async let`** for a fixed small set of child ops:

  ```swift
  async let a = API.fetchJSON(urlA)
  async let b = API.fetchJSON(urlB)
  let (ra, rb) = try await (a, b)
  ```

* **Task group** when the number of tasks is dynamic:

  ```swift
  try await withThrowingTaskGroup(of: Result.self) { group in
    for url in urls {
      group.addTask { try await API.fetchJSON(url) }
    }
    for try await item in group { results.append(item) }
  }
  ```

### D. Cancellation & timeouts

* Check **`Task.isCancelled`**, propagate cancellation from parent tasks, use **`withTaskCancellationHandler`** and **`withTimeout`** (or your own timeout wrapper).
* Naming tasks makes debugging easier in 6.2 (show up in LLDB). ([Swift.org][1])

### E. Avoid `Task.detached` by default

* Prefer `Task { ... }` (inherits actor context & priority). Reach for `Task.detached` only for advanced isolation needs; `@concurrent` eliminates many of the old uses. ([Swift.org][1])

---

## 3) Structuring state: actors, singletons, and globals

* **One source of truth per mutable state domain.** Wrap mutable caches/stores in an `actor` or keep them main‑actor isolated (now easy with default isolation = MainActor).
* **Global/static state**: prefer actor‑guarded access. If you keep it on the main actor, document it clearly.

```swift
actor ImageCache {
  private var store: [URL: Image] = [:]
  func get(_ url: URL) -> Image? { store[url] }
  func set(_ url: URL, _ image: Image) { store[url] = image }
}
```

* With default isolation = MainActor, even simple `static` dictionaries used from UI code stay safe by default. Use `@concurrent` around the I/O/CPU boundaries that *must* run off the actor. ([Swift.org][1])

---

## 4) `nonisolated`, `Sendable`, and friends (what still matters)

* **Prefer value types** and adopt **`Sendable`** where data crosses concurrency domains. Use **`@unchecked Sendable`** only as a last resort (and document why). Strict checking will call out the risky bits. ([Swift.org][2])
* **`nonisolated`**: use when a method doesn’t touch isolated state. After enabling the upcoming inheritance feature, `nonisolated async` runs on the caller’s actor, which often matches intent better for UI. Keep heavy work **`@concurrent`**. ([Swift.org][1])
* **Avoid `nonisolated(unsafe)`** except during migrations you fully understand. The migration guide and diagnostics are explicit about its risks. ([Swift.org][2])

---

## 5) Packages vs. app targets (gotchas)

* **App/UI targets**: flipping **Default Actor Isolation = MainActor** is usually a net win: less annotation noise, safer defaults. ([Apple Developer][4])
* **Packages**: default remains **nonisolated**; choose per target with `.defaultIsolation(MainActor.self)` when a package is UI‑facing or intentionally single‑threaded. Keep core logic packages nonisolated unless you truly want serialization. ([Apple Developer][3])

---

## 6) Migration playbook (works for existing codebases)

1. **Turn on strict checking (warnings)** on one module at a time; fix the loudest violations first. ([Swift.org][2])
2. **Enable Default Actor Isolation = MainActor** for your **app** target. Watch how many `@MainActor` you can delete. Keep heavy/parallel work isolated behind **`@concurrent`** functions. ([Apple Developer][4])
3. **For SPM targets**, add `.defaultIsolation(MainActor.self)` selectively (UI, adapters). Leave algorithmic libraries nonisolated. ([Apple Developer][3])
4. **Adopt the upcoming async inheritance feature** when the codebase is close to green; let migration tooling suggest `@concurrent` where needed. ([Swift.org][1])
5. **Refactor singletons into actors** or ensure they’re isolated to a single actor.
6. **Replace GCD hops** with actor‑aware code (`MainActor`, `@concurrent`, structured concurrency).
7. **Name your tasks** and use 6.2’s improved async debugging to trace execution. ([Swift.org][1])

---

## 7) Do’s & Don’ts

**Do**

* Use **default MainActor isolation** for UI modules. ([Apple Developer][4])
* **Fence heavy work** behind **`@concurrent`** functions. ([Swift.org][1])
* Prefer **structured concurrency** (`async let`, task groups) over ad‑hoc tasks.
* Make cross‑actor data **`Sendable`**. ([Swift.org][2])
* Name tasks; embrace LLDB’s improved async stepping. ([Swift.org][1])

**Don’t**

* Assume `async` means “off the main thread.”
* Spam `Task.detached {}`; it usually fights the model.
* Reach for `nonisolated(unsafe)` unless you’re deliberately carving a migration escape hatch. ([Swift.org][2])

---

## 8) Extra: what else ships in 6.2 that helps

* **Migration tooling** to adopt upcoming features with warnings + fix‑its. ([Swift.org][1])
* **Foundation notifications** now have type‑safe forms that declare whether they’re main‑actor or async messages—less guesswork across actor boundaries. ([Swift.org][1])
* **Async debugging**: better stepping through actor hops and named tasks in backtraces. ([Swift.org][1])

---

## 9) Worked example: main‑actor ViewModel + explicit parallelism

```swift
// Target defaultIsolation = MainActor

struct PhotosViewModel {
  private let cache = ImageCache()

  func loadThumbnails(for urls: [URL]) async throws -> [CGImage] {
    // parallel I/O + decode off the main actor
    return try await withThrowingTaskGroup(of: CGImage.self) { group in
      for url in urls {
        group.addTask {
          if let cached = await cache.get(url) { return cached }
          let image = try await fetchAndDecode(url)
          await cache.set(url, image)
          return image
        }
      }
      var images: [CGImage] = []
      for try await img in group { images.append(img) }
      return images
    }
  }

  @concurrent
  private func fetchAndDecode(_ url: URL) async throws -> CGImage {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try decode(data) // CPU heavy decode
  }
}
```

* The ViewModel stays **main‑actor isolated by default**, but `fetchAndDecode` makes the hop explicit with **`@concurrent`**. Clean. Predictable. Testable. ([Swift.org][1])

---

## References (worth bookmarking)

* **Swift 6.2 Release blog** — authoritative overview of *Approachable Concurrency*, `@concurrent`, default MainActor isolation, migration tooling, and debugging improvements. ([Swift.org][1])
* **What’s new in Swift (Apple)** — high‑level overview including concurrency updates and `@concurrent`. ([Apple Developer][4])
* **Enable Complete Concurrency Checking** (swift.org docs) — flags and Xcode settings for strict checking. ([Swift.org][2])
* **SwiftPM `.defaultIsolation(MainActor.self)`** — set default actor isolation for packages/targets. ([Apple Developer][3])
* **Default isolation for packages is nonisolated unless set** (forums) — clarifies SPM defaults. ([Swift Forums][5])

---

Want this tailored to your codebase (targets, SPM layout, deployment OS)? Send me a quick sketch of your modules and I’ll map which ones should be MainActor‑by‑default and where to introduce `@concurrent`.

[1]: https://swift.org/blog/swift-6.2-released/ "Swift 6.2 Released | Swift.org"
[2]: https://swift.org/documentation/concurrency/ "Enabling Complete Concurrency Checking | Swift.org"
[3]: https://developer.apple.com/documentation/packagedescription/swiftsetting/defaultisolation%28_%3A_%3A%29?utm_source=chatgpt.com "defaultIsolation(_:_:) | Apple Developer Documentation"
[4]: https://developer.apple.com/swift/whats-new/ "What’s New - Swift - Apple Developer"
[5]: https://forums.swift.org/t/what-is-the-default-isolation-mode-for-swift-packages-6-2/80453?utm_source=chatgpt.com "What is the default isolation mode for Swift packages (6.2+)?"
