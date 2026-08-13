enum WordNavigationDirection {
    case backward
    case forward
}

/// Shared readline-style word classification and cursor movement.
enum WordNavigation {
    private static let punctuation: Set<Character> = Set("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static func isBoundary(_ character: Character) -> Bool {
        character.isWhitespace || self.punctuation.contains(character)
    }

    static func destination(
        in text: String,
        from cursor: Int,
        direction: WordNavigationDirection,
        isBoundary: (Character) -> Bool = WordNavigation.isBoundary) -> Int
    {
        let characters = Array(text)
        var index = min(max(cursor, 0), characters.count)

        switch direction {
        case .forward:
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }

            if index < characters.count {
                let isPunctuation = isBoundary(characters[index]) && !characters[index].isWhitespace
                if isPunctuation {
                    while index < characters.count,
                          isBoundary(characters[index]),
                          !characters[index].isWhitespace
                    {
                        index += 1
                    }
                } else {
                    while index < characters.count,
                          !characters[index].isWhitespace,
                          !isBoundary(characters[index])
                    {
                        index += 1
                    }
                }
            }

        case .backward:
            while index > 0, characters[index - 1].isWhitespace {
                index -= 1
            }

            if index > 0 {
                let isPunctuation = isBoundary(characters[index - 1]) && !characters[index - 1].isWhitespace
                if isPunctuation {
                    while index > 0,
                          isBoundary(characters[index - 1]),
                          !characters[index - 1].isWhitespace
                    {
                        index -= 1
                    }
                } else {
                    while index > 0,
                          !characters[index - 1].isWhitespace,
                          !isBoundary(characters[index - 1])
                    {
                        index -= 1
                    }
                }
            }
        }

        return index
    }
}
