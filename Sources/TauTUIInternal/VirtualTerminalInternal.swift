// Internal target wrapper around VirtualTerminal to keep it out of the public API.
@_exported import TauTUI

// Re-export VirtualTerminal for tests/fixtures without exposing it via the main library.
public typealias VirtualTerminalInternal = VirtualTerminal
