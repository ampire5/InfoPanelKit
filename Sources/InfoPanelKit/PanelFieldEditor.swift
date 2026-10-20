import AppKit

/// The window's field editor for the panel's values (the app returns it from `windowWillReturnFieldEditor` for the
/// panel's fields): selecting a value makes it the first responder, and then only ⌘C with text selected (copies it)
/// and ⌘A (selects the value) are its own (an app may have no Edit menu to do them). Every other key, ⌘C with nothing
/// selected and the app's ⌘ and ⌃ bindings too, is still the app's: `onPlainKey` hands it back.
public final class PanelFieldEditor: NSTextView {
    public var onPlainKey: ((NSEvent) -> Void)?
    /// Where ⌘C puts the selected text (tests give their own).
    var pasteboard: NSPasteboard = .general

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.subtracting(.capsLock) == .command {
            // Key codes, so ⌘C copies on any keyboard layout (a Russian "с" is still the C key).
            switch event.keyCode {
            case 8 where selectedRange().length > 0:   // kVK_ANSI_C
                pasteboard.clearContents()
                pasteboard.setString((string as NSString).substring(with: selectedRange()), forType: .string)
                return
            case 0: selectAll(nil); return   // kVK_ANSI_A
            default: break
            }
        }
        if let onPlainKey {
            onPlainKey(event)
            return
        }
        super.keyDown(with: event)
    }
}
