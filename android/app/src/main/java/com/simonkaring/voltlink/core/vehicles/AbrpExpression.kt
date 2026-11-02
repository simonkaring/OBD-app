package com.simonkaring.voltlink.core.vehicles

/**
 * Byte-math evaluator for ABRP (A Better Routeplanner) PID equations.
 *
 * A port of the iOS `ABRPGenericVehicleProfile.evaluate`: equations address response bytes by
 * spreadsheet-column letter (`A` = byte 0, `aa` = byte 26), with `Signed()`, `{token:bit}`,
 * `INT16(hi:lo)` and `<<n` shorthands. Anything that is not arithmetic after substitution is
 * rejected, so a malformed equation yields no value instead of a crash mid-drive.
 */
internal object AbrpExpression {
    private val int16 = Regex("(?i)INT16\\(([A-Za-z]{1,2}):([A-Za-z]{1,2})\\)")
    private val bit = Regex("\\{([A-Za-z]{1,2}):([0-9]+)\\}")
    private val signed = Regex("(?i)signed\\(([A-Za-z]{1,2})\\)")
    private val token = Regex("\\b[A-Za-z]{1,2}\\b")
    private val arithmetic = Regex("^[0-9.+*/() -]+$")

    /** A..Z = 0..25, aa..az = 26..51, ba.. = 52.. — ABRP uses spreadsheet columns. */
    fun byteIndexForToken(value: String): Int? {
        if (value.isEmpty() || value.length > 2) return null
        val columns = value.uppercase().map { it - 'A' }
        if (columns.any { it !in 0..25 }) return null
        return when (columns.size) {
            1 -> columns[0]
            else -> (columns[0] + 1) * 26 + columns[1]
        }
    }

    /** Returns null when the equation cannot be evaluated against these bytes. */
    fun evaluate(equation: String, bytes: ByteArray): Double? {
        var expr = equation.trim()
        if (expr.isEmpty()) return null

        expr = int16.replace(expr) { match ->
            val high = match.groupValues[1]
            val low = match.groupValues[2]
            "((Signed($high)*256)+$low)"
        }

        while (true) {
            val match = bit.find(expr) ?: break
            val index = byteIndexForToken(match.groupValues[1]) ?: return null
            val bitIndex = match.groupValues[2].toIntOrNull() ?: return null
            if (index >= bytes.size || bitIndex !in 0..7) return null
            val isSet = ((bytes[index].toInt() and 0xFF) shr bitIndex) and 1 == 1
            expr = expr.replaceRange(match.range, if (isSet) "1" else "0")
        }

        // Boolean folding, exactly as the iOS port does it: `!` flips a literal, then the
        // operators degrade to arithmetic so `&&`/`||` results can be summed.
        var previous = ""
        while (previous != expr) {
            previous = expr
            expr = expr.replace("!1", "0").replace("!0", "1")
        }
        expr = expr.replace("&&", "*").replace("||", "+")

        while (true) {
            val match = signed.find(expr) ?: break
            val index = byteIndexForToken(match.groupValues[1]) ?: return null
            if (index >= bytes.size) return null
            // Byte is already signed in Kotlin, so a raw cast gives -128..127.
            expr = expr.replaceRange(match.range, "(${bytes[index].toInt()})")
        }

        while (true) {
            val match = token.find(expr) ?: break
            val index = byteIndexForToken(match.value) ?: return null
            if (index >= bytes.size) return null
            expr = expr.replaceRange(match.range, "(${bytes[index].toInt() and 0xFF})")
        }

        expr = expr.replace("<<8", "*256").replace("<<16", "*65536").replace("<<32", "*4294967296")

        val clean = expr.replace("--", "+")
        if (!arithmetic.matches(clean)) return null
        val value = Parser(clean).parse() ?: return null
        return if (value.isFinite()) value else null
    }

    /** Recursive-descent evaluator for `+ - * / ( )` over the substituted expression. */
    private class Parser(private val text: String) {
        private var position = 0

        fun parse(): Double? {
            val value = expression() ?: return null
            skipSpaces()
            return if (position == text.length) value else null
        }

        private fun expression(): Double? {
            var value = term() ?: return null
            while (true) {
                skipSpaces()
                val operator = peek()
                if (operator != '+' && operator != '-') return value
                position++
                val right = term() ?: return null
                value = if (operator == '+') value + right else value - right
            }
        }

        private fun term(): Double? {
            var value = unary() ?: return null
            while (true) {
                skipSpaces()
                val operator = peek()
                if (operator != '*' && operator != '/') return value
                position++
                val right = unary() ?: return null
                value = if (operator == '*') value * right else value / right
            }
        }

        private fun unary(): Double? {
            skipSpaces()
            return when (peek()) {
                '-' -> {
                    position++
                    unary()?.let { -it }
                }
                '+' -> {
                    position++
                    unary()
                }
                else -> primary()
            }
        }

        private fun primary(): Double? {
            skipSpaces()
            if (peek() == '(') {
                position++
                val value = expression() ?: return null
                skipSpaces()
                if (peek() != ')') return null
                position++
                return value
            }
            val start = position
            while (position < text.length && (text[position].isDigit() || text[position] == '.')) {
                position++
            }
            if (start == position) return null
            return text.substring(start, position).toDoubleOrNull()
        }

        private fun peek(): Char? = if (position < text.length) text[position] else null

        private fun skipSpaces() {
            while (position < text.length && text[position].isWhitespace()) position++
        }
    }
}
