import Foundation

/// Spoken-only normalization. Never changes the user's displayed math or source code.
enum SpeechRendering {
    static let delivery = "Speak conversationally, with short natural pauses at punctuation and between ideas. Keep warmth and rhythm subtle. Read supplied um or uh naturally, but do not invent filler, laughter or dramatic emotion. Keep technical quantities clear and unhurried."
    private static let units: [String:String] = ["kg":"kilogram","mg":"milligram","g":"gram","km":"kilometer","cm":"centimeter","mm":"millimeter","m":"meter","ms":"millisecond","s":"second","min":"minute","h":"hour","mol":"mole","K":"kelvin","A":"ampere","N":"newton","Pa":"pascal","J":"joule","W":"watt","V":"volt","Hz":"hertz","L":"liter","mL":"milliliter"]
    private static let unit = "(?:mol|min|kg|mg|km|cm|mm|ms|Pa|Hz|mL|g|m|s|h|K|A|N|J|W|V|L)"
    static func text(_ source:String) -> String {
        var source=source
        source=source.replacingOccurrences(of:#"(?s)\$\$(.*?)\$\$"#,with:"$1",options:.regularExpression)
        source=source.replacingOccurrences(of:#"\$([^$\n]+)\$"#,with:"$1",options:.regularExpression)
        source=source.replacingOccurrences(of:#"\\[()\[\]]"#,with:"",options:.regularExpression)
        source=source.replacingOccurrences(of:#"\\(?:mathrm|text|operatorname)\{([^{}]+)\}"#,with:"$1",options:.regularExpression)
        source=source.replacingOccurrences(of:#"\^\{(-?[0-9]+)\}"#,with:"^$1",options:.regularExpression)
        source=source.replacingOccurrences(of:"\\cdot",with:"*").replacingOccurrences(of:"\\times",with:" times ").replacingOccurrences(of:"\\,",with:" ")
        source=source.replacingOccurrences(of:#"\\frac\{([^{}]+)\}\{([^{}]+)\}"#,with:"$1/$2",options:.regularExpression)
        source=source.replacingOccurrences(of:#"\s*([*/])\s*"#,with:"$1",options:.regularExpression)
        var text=source.replacingOccurrences(of:"·",with:"*").replacingOccurrences(of:"⋅",with:"*")
        for (symbol,power) in [("⁻¹","^-1"),("⁻²","^-2"),("⁻³","^-3"),("²","^2"),("³","^3")] {text=text.replacingOccurrences(of:symbol,with:power)}
        func replace(_ pattern:String,_ body:(NSTextCheckingResult,NSString)->String) {
            guard let regex=try? NSRegularExpression(pattern:pattern) else{return}
            let original=text as NSString
            for match in regex.matches(in:text,range:NSRange(location:0,length:original.length)).reversed() {
                text=(text as NSString).replacingCharacters(in:match.range,with:body(match,original))
            }
        }
        replace(#"\b(\d+(?:\.\d+)?)[eE]([+-]?\d+)\b"#) {m,t in
            t.substring(with:m.range(at:1))+" times ten to the power of "+t.substring(with:m.range(at:2)).replacingOccurrences(of:"-",with:"minus ").replacingOccurrences(of:"+",with:"")
        }
        let atom=unit+"(?:\\^-?[1-9][0-9]?)?"
        let expression="(?>"+atom+")(?:(?:[*/]|\\s+)?(?>"+atom+"))*+"
        replace("(?<![\\p{L}\\p{N}])(?:([0-9]+(?:\\.[0-9]+)?)\\s*)?("+expression+")(?![\\p{L}\\p{N}])") {m,t in
            let raw=t.substring(with:m.range(at:2));let number=m.range(at:1).location == NSNotFound ? nil : t.substring(with:m.range(at:1))
            let rx=try! NSRegularExpression(pattern:"("+unit+")(?:\\^(-?[1-9][0-9]?))?|([*/])")
            let parts=rx.matches(in:raw,range:NSRange(location:0,length:(raw as NSString).length))
            // A lone variable such as m or s in prose is not silently turned into a unit.
            guard number != nil || parts.count>1 || raw.contains("^") else{return t.substring(with:m.range)}
            var numerator:[String]=[],denominator:[String]=[],dividing=false
            for part in parts {
                if part.range(at:3).location != NSNotFound { if (raw as NSString).substring(with:part.range(at:3)) == "/" {dividing=true};continue }
                let key=(raw as NSString).substring(with:part.range(at:1));var name=units[key] ?? key
                let power=part.range(at:2).location == NSNotFound ? 1 : (Int((raw as NSString).substring(with:part.range(at:2))) ?? 1)
                let below=dividing || power<0, magnitude=abs(power)
                if !below && (magnitude>1 || number.map{Double($0) != 1} == true),name != "hertz" {name += "s"}
                if magnitude == 2 {name += " squared"} else if magnitude == 3 {name += " cubed"} else if magnitude != 1 {name += " to the power of "+String(magnitude)}
                if below {denominator.append(name)} else {numerator.append(name)}
            }
            var spoken=numerator.joined(separator:" ")
            if !denominator.isEmpty {spoken += (spoken.isEmpty ? "per " : " per ")+denominator.joined(separator:" ")}
            return (number.map{$0+" "} ?? "")+spoken
        }
        replace(#"(?<![\p{L}])([0-9]+(?:\.[0-9]+)?)\^(-?[0-9]+)"#) {m,t in
            t.substring(with:m.range(at:1))+" to the power of "+t.substring(with:m.range(at:2)).replacingOccurrences(of:"-",with:"minus ")
        }
        text=text.replacingOccurrences(of:#"(?i)\blol\b"#,with:"ha",options:.regularExpression)
        for (symbol,spoken) in [("°C"," degrees Celsius"),("°F"," degrees Fahrenheit"),("±"," plus or minus "),("≤"," less than or equal to "),("≥"," greater than or equal to "),("×"," times "),("÷"," divided by ")] {text=text.replacingOccurrences(of:symbol,with:spoken)}
        return text.replacingOccurrences(of:" {2,}",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

enum RecognitionPacing {
    static let hints=["Iris","AriZe","VoiceBox","Gemini","LM Studio","kilograms","meters squared","hybridisation","orbital","neuron","derivative","integral"]
    static func pause(after text:String)->Double {
        let last=text.lowercased().split{!$0.isLetter}.last.map(String.init) ?? ""
        return ["and","or","but","because","with","um","uh","the","to"].contains(last) ? 2.7 : 1.9
    }
}
