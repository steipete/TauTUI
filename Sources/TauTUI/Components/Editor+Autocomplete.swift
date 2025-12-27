import Foundation

extension Editor {
    func triggerAutocomplete(explicit: Bool) {
        guard let provider = self.autocompleteProvider else { return }
        if explicit, !provider.shouldTriggerFileCompletion(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        {
            return
        }

        let suggestion = provider.getSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)

        if let suggestion {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.cancelAutocomplete()
        }
    }

    func updateAutocomplete() {
        guard let provider = self.autocompleteProvider, self.isAutocompleting else { return }

        let suggestion = provider.getSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)

        if let suggestion {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.cancelAutocomplete()
        }
    }

    func cancelAutocomplete() {
        self.isAutocompleting = false
        self.autocompleteList = nil
        self.autocompletePrefix = ""
    }

    func applySelectedAutocompleteItem() {
        guard let provider = self.autocompleteProvider,
              let list = self.autocompleteList,
              let selected = list.selectedItem()
        else {
            self.cancelAutocomplete()
            return
        }

        let autocompleteItem = AutocompleteItem(
            value: selected.value,
            label: selected.label,
            description: selected.description)

        let result = provider.applyCompletion(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol,
            item: autocompleteItem,
            prefix: self.autocompletePrefix)

        self.buffer = self.withMutatingBuffer { buf in
            buf.lines = result.lines
            buf.cursorLine = result.cursorLine
            buf.cursorCol = result.cursorCol
        }

        self.cancelAutocomplete()
        self.onChange?(self.getText())
    }

    func handleTabCompletion() {
        guard self.autocompleteProvider != nil else { return }
        let currentLine = self.buffer.lines[self.buffer.cursorLine]
        let cursorIndex = currentLine.index(
            currentLine.startIndex,
            offsetBy: min(self.buffer.cursorCol, currentLine.count))
        let beforeCursor = String(currentLine[..<cursorIndex])

        if beforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            self.handleSlashCommandCompletion()
        } else {
            self.forceFileAutocomplete()
        }
    }

    func handleSlashCommandCompletion() {
        self.triggerAutocomplete(explicit: true)
    }

    func forceFileAutocomplete() {
        guard let provider = self.autocompleteProvider else { return }
        if let suggestion = provider.forceFileSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.triggerAutocomplete(explicit: true)
        }
    }

    func presentAutocomplete(provider: AutocompleteProvider, suggestion: AutocompleteSuggestion) {
        self.autocompletePrefix = suggestion.prefix
        self.autocompleteList = SelectList(
            items: suggestion.items
                .map { SelectItem(value: $0.value, label: $0.label, description: $0.description) },
            maxVisible: 5,
            theme: self.theme.selectList)

        self.autocompleteList?.onSelect = { [weak self] selected in
            guard let self else { return }
            let result = provider.applyCompletion(
                lines: self.buffer.lines,
                cursorLine: self.buffer.cursorLine,
                cursorCol: self.buffer.cursorCol,
                item: AutocompleteItem(
                    value: selected.value,
                    label: selected.label,
                    description: selected.description),
                prefix: self.autocompletePrefix)
            self.buffer = self.withMutatingBuffer { buf in
                buf.lines = result.lines
                buf.cursorLine = result.cursorLine
                buf.cursorCol = result.cursorCol
            }
            self.cancelAutocomplete()
            self.onChange?(self.getText())
        }

        self.autocompleteList?.onCancel = { [weak self] in self?.cancelAutocomplete() }
        self.isAutocompleting = true
    }
}

