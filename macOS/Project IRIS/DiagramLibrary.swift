import Foundation
import CoreGraphics

/// Locally authored, fixed geometry and narration. Never generated from screen content.
enum DiagramLibrary {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subject: String
        let aliases: [String]
        var drawing: ScreenDrawing { make(id) }
    }
    static let entries: [Entry] = [
        .init(id:"water-molecule",title:"Water molecule",subject:"Chemistry",aliases:["water molecule","h2o","h₂o","covalent bonding"]),
        .init(id:"atom",title:"Inside an atom",subject:"Chemistry",aliases:["atomic structure","structure of an atom","bohr model","atom"]),
        .init(id:"ionic-bond",title:"Ionic bonding",subject:"Chemistry",aliases:["ionic bond","sodium chloride","nacl"]),
        .init(id:"reaction-energy",title:"Reaction energy",subject:"Chemistry",aliases:["activation energy","reaction energy","energy profile"]),
        .init(id:"electric-circuit",title:"A complete circuit",subject:"Physics",aliases:["electric circuit","electrical circuit","simple circuit","ohm's law","ohms law"]),
        .init(id:"wave",title:"Anatomy of a wave",subject:"Physics",aliases:["transverse wave","wavelength","wave amplitude"]),
        .init(id:"heat-transfer",title:"Three ways heat moves",subject:"Physics",aliases:["heat transfer","thermal conductivity","conduction","convection"]),
        .init(id:"animal-cell",title:"Inside an animal cell",subject:"Biology",aliases:["animal cell","cell structure","cell organelles"]),
        .init(id:"photosynthesis",title:"Photosynthesis",subject:"Biology",aliases:["photosynthesis","plant energy"]),
        .init(id:"circulation",title:"Double circulation",subject:"Biology",aliases:["blood circulat","circulatory","double circulation"]),
        .init(id:"dna",title:"DNA & base pairing",subject:"Biology",aliases:["dna","base pair","double helix"]),
        .init(id:"client-server",title:"A web request",subject:"Computer science",aliases:["client server","client-server","http request","web request"]),
        .init(id:"binary-tree",title:"Binary search tree",subject:"Computer science",aliases:["binary search tree","binary tree","bst"]),
        .init(id:"neural-network",title:"A neural network",subject:"Computer science",aliases:["neural network","feedforward","deep learning"]),
        .init(id:"water-cycle",title:"The water cycle",subject:"Earth science",aliases:["water cycle","hydrologic cycle"]),
        .init(id:"solar-system",title:"Our solar system",subject:"Astronomy",aliases:["solar system","order of planets"])
        ,.init(id:"atomic-orbitals",title:"s and p orbitals",subject:"Chemistry",aliases:["atomic orbitals","s and p orbitals"])
        ,.init(id:"hybridisation",title:"sp³ hybridisation",subject:"Chemistry",aliases:["sp3 hybrid", "sp³ hybrid", "hybridisation", "hybridization"])
        ,.init(id:"hybridisation-sp2",title:"sp² hybrid orbitals",subject:"Chemistry",aliases:["sp2 hybrid", "sp² hybrid"])
        ,.init(id:"neuron",title:"A complete neuron",subject:"Biology",aliases:["neuron", "neurone", "nerve cell"])
        ,.init(id:"digestive-system",title:"Human digestive system",subject:"Biology",aliases:["digestive system", "digestion"])
    ]
    static func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
    static func match(_ prompt: String) -> Entry? {
        let text=prompt.lowercased()
        guard ScreenQuestionPolicy.wantsNewDrawing(prompt), !["custom", "my own", "not a preset", "don't use a preset", "do not use a preset", "compare", "versus", " vs ", "calculate", "solve", "derive", "replication", "transcription", "backpropagation", "blackbody", "quantum", "calvin cycle", "coronary", "electrical conduction"].contains(where:text.contains) else{return nil}
        let matches = entries.filter { entry in entry.aliases.contains { alias in
            guard let range=text.range(of:alias) else{return false}
            let before=range.lowerBound == text.startIndex || !text[text.index(before:range.lowerBound)].isLetter
            let after=alias == "blood circulat" || range.upperBound == text.endIndex || !text[range.upperBound].isLetter || text[range.upperBound] == "s"
            return before && after
        } }
        if matches.count == 1 {return matches.first}
        if text.contains("sp2") || text.contains("sp²") {return matches.first{$0.id=="hybridisation-sp2"}}
        return nil
    }
    private struct Plate {
        var marks:[ScreenDrawing.Mark]=[]
        var step=0
        mutating func stage(_ speech:String,_ body:(inout Plate)->Void) {
            let first=marks.count;body(&self)
            if marks.count>first {marks[first].speech=speech;for i in first..<marks.count{marks[i].step=step};step+=1}
        }
        mutating func ellipse(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ color:String="cyan", filled:Bool=false) {marks.append(.init(kind:"circle",x:x,y:y,width:w,height:h,color:color,closed:filled))}
        mutating func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ color:String="cyan") {marks.append(.init(kind:"rectangle",x:x,y:y,width:w,height:h,color:color))}
        mutating func arrow(_ x:Double,_ y:Double,_ dx:Double,_ dy:Double,_ color:String="cyan") {marks.append(.init(kind:"arrow",x:x,y:y,width:dx,height:dy,color:color))}
        mutating func line(_ points:[(Double,Double)],_ color:String="cyan",closed:Bool=false) {
            marks.append(.init(kind:"path",x:0,y:0,width:1,height:1,color:color,points:points.map{DrawingPoint(x:$0.0,y:$0.1)},closed:closed))
        }
        mutating func curve(_ points:[DrawingPoint],_ color:String="cyan",closed:Bool=false) {marks.append(.init(kind:"path",x:0,y:0,width:1,height:1,color:color,points:points,closed:closed))}
        mutating func label(_ text:String,_ x:Double,_ y:Double,_ w:Double=0.18,_ color:String="white") {marks.append(.init(kind:"caption",x:x,y:y,width:w,height:0.035,text:text,color:color))}
        mutating func object(_ name:String,_ x:Double,_ y:Double,_ w:Double,_ h:Double) {marks.append(.init(kind:"object",x:x,y:y,width:w,height:h,object:name))}
    }
    static func make(_ id:String) -> ScreenDrawing {
        var p=Plate()
        switch id {
        case "water-molecule":
            p.stage("A water molecule has one oxygen atom and two hydrogen atoms, sharing electrons in covalent bonds.") {p in
                p.line([(0.50,0.43),(0.34,0.60)],"white");p.line([(0.50,0.43),(0.66,0.60)],"white")
                p.ellipse(0.44,0.34,0.12,0.18,"red",filled:true);p.label("O",0.475,0.40,0.05,"red")
                for x in [0.29,0.62]{p.ellipse(x,0.56,0.09,0.13,"cyan",filled:true);p.label("H",x+0.027,0.60,0.04,"cyan")}
            }
            p.stage("Oxygen attracts the shared electrons more strongly. The molecule is bent and polar, rather than a straight line.") {p in
                p.label("δ−",0.485,0.29,0.05,"red");p.label("δ+",0.30,0.70,0.06,"cyan");p.label("δ+",0.63,0.70,0.06,"cyan")
                p.label("Bent shape · polar covalent bonds",0.32,0.25,0.38)
            }
        case "atom":
            p.stage("This reference illustrates a helium atom. The diffuse electron cloud represents a probability distribution around the small central nucleus, rather than fixed planetary paths.") {p in
                p.ellipse(0.31,0.30,0.38,0.40,"blue");p.ellipse(0.40,0.39,0.20,0.22,"cyan")
                p.ellipse(0.46,0.45,0.08,0.10,"orange",filled:true);p.label("Nucleus",0.59,0.46,0.15,"orange")
            }
            p.stage("The inset enlarges the nucleus, containing protons and neutrons. The nucleus and surrounding electron cloud are represented on very different scales; the image is not a literal photograph of an atom.") {p in
                for (x,y) in [(0.405,0.465),(0.665,0.47),(0.48,0.295)]{p.ellipse(x,y,0.025,0.035,"cyan",filled:true)}
                p.label("Electrons −",0.18,0.32,0.15,"cyan");p.label("Protons +  /  neutrons",0.56,0.54,0.25,"orange")
                p.label("Illustrative shell model · not to scale",0.31,0.72,0.40)
            }
        case "ionic-bond":
            p.stage("Sodium has one outer electron available to transfer. Chlorine can accept that electron to complete its outer shell.") {p in
                p.ellipse(0.22,0.36,0.18,0.26,"orange");p.label("Na",0.28,0.46,0.06,"orange")
                p.ellipse(0.60,0.36,0.18,0.26,"green");p.label("Cl",0.66,0.46,0.06,"green")
                p.ellipse(0.39,0.46,0.014,0.02,"yellow");p.arrow(0.42,0.47,0.15,0,"yellow");p.label("electron transfer",0.41,0.40,0.18,"yellow")
            }
            p.stage("After transfer, sodium is a positive ion and chloride is a negative ion. Electrostatic attraction holds opposite ions together in an ionic lattice.") {p in
                p.label("Na⁺",0.26,0.64,0.10,"orange");p.label("Cl⁻",0.64,0.64,0.10,"green")
                p.arrow(0.45,0.60,0.10,0,"white");p.arrow(0.55,0.60,-0.10,0,"white")
                p.label("Opposite charges attract",0.36,0.71,0.30)
            }
        case "reaction-energy":
            p.stage("An energy profile plots potential energy against reaction progress. This example is exothermic: products finish lower than reactants.") {p in
                p.arrow(0.22,0.70,0,-0.40,"white");p.arrow(0.22,0.70,0.58,0,"white")
                p.label("Potential energy",0.13,0.25,0.22);p.label("Reaction progress →",0.43,0.72,0.30)
                p.curve([.init(x:0.26,y:0.55),.init(x:0.51,y:0.33,cx:0.38,cy:0.55,c2x:0.40,c2y:0.33),.init(x:0.76,y:0.63,cx:0.62,cy:0.33,c2x:0.62,c2y:0.63)],"orange")
            }
            p.stage("Activation energy is the barrier from the reactants to the peak. A catalyst lowers that barrier without changing the energy difference between reactants and products.") {p in
                p.arrow(0.39,0.55,0,-0.20,"yellow");p.label("Eₐ",0.32,0.41,0.06,"yellow")
                p.curve([.init(x:0.26,y:0.55),.init(x:0.51,y:0.44,cx:0.38,cy:0.55,c2x:0.40,c2y:0.44),.init(x:0.76,y:0.63,cx:0.62,cy:0.44,c2x:0.62,c2y:0.63)],"green")
                p.label("Reactants",0.23,0.57,0.13);p.label("Products",0.69,0.65,0.13);p.label("Catalysed route",0.57,0.46,0.20,"green")
            }
        case "electric-circuit":
            p.stage("A battery supplies a potential difference. A complete loop lets charge move through the circuit.") {p in
                p.line([(0.30,0.44),(0.30,0.32),(0.45,0.32)],"cyan");p.line([(0.55,0.32),(0.70,0.32),(0.70,0.68),(0.30,0.68),(0.30,0.56)],"cyan")
                p.line([(0.26,0.44),(0.34,0.44)],"orange");p.line([(0.28,0.56),(0.32,0.56)],"orange")
                p.label("+",0.22,0.42,0.03,"orange");p.label("−",0.22,0.54,0.03,"orange");p.label("Battery",0.15,0.60,0.12,"orange")
            }
            p.stage("The resistor limits current. For an ohmic resistor at constant temperature, voltage equals current multiplied by resistance.") {p in
                p.box(0.45,0.295,0.10,0.05,"yellow");p.label("Resistor R",0.43,0.25,0.16,"yellow")
                p.arrow(0.57,0.32,0.08,0,"yellow");p.label("Conventional current I",0.43,0.60,0.27,"cyan");p.label("V = I × R",0.45,0.46,0.16)
            }
        case "wave":
            p.stage("A transverse wave oscillates perpendicular to its direction of travel. The center line is the equilibrium position.") {p in
                p.line([(0.18,0.50),(0.82,0.50)],"white")
                p.curve([.init(x:0.18,y:0.50),.init(x:0.34,y:0.50,cx:0.23,cy:0.23,c2x:0.29,c2y:0.23),.init(x:0.50,y:0.50,cx:0.39,cy:0.77,c2x:0.45,c2y:0.77),.init(x:0.66,y:0.50,cx:0.55,cy:0.23,c2x:0.61,c2y:0.23),.init(x:0.82,y:0.50,cx:0.71,cy:0.77,c2x:0.77,c2y:0.77)],"cyan")
            }
            p.stage("Amplitude is measured from equilibrium to a crest. Wavelength is the distance between matching points on consecutive cycles.") {p in
                p.arrow(0.26,0.50,0,-0.20,"orange");p.label("Amplitude A",0.13,0.35,0.14,"orange")
                p.arrow(0.26,0.26,0.32,0,"green");p.arrow(0.58,0.26,-0.32,0,"green");p.label("Wavelength λ",0.34,0.22,0.18,"green")
                p.arrow(0.65,0.72,0.14,0,"yellow");p.label("Travel →",0.52,0.70,0.12,"yellow");p.label("v = fλ",0.43,0.68,0.10)
            }
        case "heat-transfer":
            p.stage("Conduction transfers thermal energy through material, without bulk movement of that material. A hot end passes energy toward a cooler end.") {p in
                p.box(0.15,0.41,0.19,0.08,"orange");p.label("HOT",0.15,0.36,0.07,"red");p.label("COOL",0.27,0.36,0.08,"cyan");p.arrow(0.19,0.45,0.10,0,"yellow");p.label("Conduction",0.16,0.65,0.18)
            }
            p.stage("Convection involves moving fluid. In this example, warmer fluid rises while cooler fluid descends, forming a circulation loop.") {p in
                p.box(0.42,0.36,0.17,0.24,"blue");p.arrow(0.46,0.55,0,-0.13,"red");p.arrow(0.55,0.41,0,0.13,"cyan");p.arrow(0.47,0.40,0.06,0,"red");p.arrow(0.54,0.56,-0.06,0,"cyan");p.label("Convection",0.42,0.65,0.18)
            }
            p.stage("Radiation transfers energy through electromagnetic waves. Unlike conduction or convection, it can carry energy across empty space.") {p in
                p.object("sun",0.66,0.34,0.14,0.20)
                p.curve([.init(x:0.66,y:0.55),.init(x:0.80,y:0.59,cx:0.68,cy:0.47,c2x:0.77,c2y:0.66)],"yellow")
                p.label("Radiation",0.66,0.65,0.18)
            }
        case "animal-cell":
            p.stage("An animal cell has a flexible outer membrane surrounding cytoplasm. This illustration shows selected organelles, not their exact sizes or numbers.") {p in
                p.curve([.init(x:0.30,y:0.34),.init(x:0.72,y:0.33,cx:0.39,cy:0.24,c2x:0.64,c2y:0.23),.init(x:0.76,y:0.64,cx:0.86,cy:0.42,c2x:0.82,c2y:0.56),.init(x:0.28,y:0.65,cx:0.64,cy:0.78,c2x:0.37,c2y:0.76),.init(x:0.30,y:0.34,cx:0.18,cy:0.55,c2x:0.20,c2y:0.41)],"cyan",closed:true)
                p.label("Cell membrane",0.13,0.28,0.19,"cyan");p.arrow(0.28,0.31,0.04,0.03,"cyan")
            }
            p.stage("The nucleus contains most of the cell's DNA. The nucleolus inside helps produce ribosomal components.") {p in
                p.ellipse(0.41,0.40,0.16,0.19,"purple",filled:true);p.ellipse(0.47,0.46,0.045,0.055,"purple",filled:true);p.label("Nucleus",0.40,0.60,0.14,"purple")
            }
            p.stage("Mitochondria participate in cellular respiration. Folded inner membranes provide space for energy-conversion processes.") {p in
                for (x,y) in [(0.62,0.40),(0.32,0.54)] {p.ellipse(x,y,0.10,0.07,"orange",filled:true);p.line([(x+0.02,y+0.035),(x+0.035,y+0.015),(x+0.05,y+0.05),(x+0.065,y+0.02),(x+0.08,y+0.035)],"orange")}
                p.label("Mitochondria",0.66,0.56,0.18,"orange")
            }
            p.stage("The endoplasmic reticulum is a membrane network involved in producing and processing proteins and lipids.") {p in
                for y in [0.38,0.40,0.42]{p.curve([.init(x:0.36,y:y),.init(x:0.61,y:y-0.04,cx:0.42,cy:y-0.06,c2x:0.56,c2y:y-0.08)],"green")}
                p.label("Endoplasmic reticulum",0.55,0.27,0.28,"green")
            }
        case "photosynthesis":
            p.stage("Light supplies the energy for photosynthesis. Leaves capture that light using photosynthetic pigments.") {p in
                p.object("sun",0.16,0.29,0.14,0.20);p.object("plant",0.42,0.32,0.18,0.31);p.arrow(0.31,0.39,0.12,0.04,"yellow");p.label("LIGHT",0.28,0.32,0.12,"yellow")
            }
            p.stage("Water reaches the plant through its roots, and carbon dioxide enters the leaves. These are inputs for making sugars.") {p in
                p.object("droplet",0.18,0.55,0.07,0.12);p.label("Water",0.15,0.68,0.12,"cyan");p.arrow(0.27,0.61,0.15,0,"blue")
                p.label("CO₂",0.69,0.34,0.10,"white");p.arrow(0.70,0.41,-0.12,0.03,"white")
            }
            p.stage("Inside chloroplasts, light energy is converted into chemical energy. Sugars store that energy, and oxygen is released. This is an overall summary, not a single chemical step.") {p in
                p.object("chloroplast",0.67,0.48,0.16,0.17);p.label("Chloroplast",0.66,0.66,0.18,"green")
                p.label("Sugars + O₂",0.41,0.70,0.21,"green");p.arrow(0.52,0.63,0,0.06,"green")
                p.label("CO₂ + H₂O + light → sugars + O₂",0.32,0.25,0.43)
            }
        case "circulation":
            p.stage("Human circulation has two linked loops. The right side of the heart pumps oxygen-poor blood to the lungs; the left side sends oxygen-rich blood to the body.") {p in
                p.curve([.init(x:0.50,y:0.46),.init(x:0.39,y:0.47,cx:0.44,cy:0.40,c2x:0.37,c2y:0.40),.init(x:0.50,y:0.60,cx:0.36,cy:0.54,c2x:0.44,c2y:0.57),.init(x:0.50,y:0.46)],"blue",closed:true)
                p.curve([.init(x:0.50,y:0.46),.init(x:0.61,y:0.47,cx:0.56,cy:0.40,c2x:0.63,c2y:0.40),.init(x:0.50,y:0.60,cx:0.64,cy:0.54,c2x:0.56,c2y:0.57),.init(x:0.50,y:0.46)],"red",closed:true)
                p.label("RIGHT",0.40,0.47,0.08,"cyan");p.label("LEFT",0.53,0.47,0.07,"red");p.label("HEART",0.44,0.59,0.12)
                p.object("lungs",0.43,0.25,0.14,0.16);p.label("LUNGS",0.61,0.28,0.12,"purple")
            }
            p.stage("The pulmonary loop carries blood from the right heart to the lungs for gas exchange, then back to the left heart.") {p in
                p.line([(0.42,0.44),(0.34,0.40),(0.34,0.31),(0.43,0.31)],"blue");p.arrow(0.37,0.31,0.05,0,"blue")
                p.line([(0.57,0.31),(0.66,0.31),(0.66,0.41),(0.58,0.44)],"red");p.arrow(0.63,0.41,-0.05,0.025,"red")
                p.label("Pulmonary loop",0.15,0.34,0.20)
            }
            p.stage("The systemic loop carries blood from the left heart through body tissues and back to the right heart. Red and blue indicate relative oxygen content, not literal blood color.") {p in
                p.line([(0.58,0.58),(0.68,0.64),(0.68,0.70),(0.54,0.70)],"red");p.arrow(0.65,0.70,-0.09,0,"red")
                p.line([(0.46,0.70),(0.32,0.70),(0.32,0.63),(0.42,0.58)],"blue");p.arrow(0.34,0.62,0.06,-0.03,"blue")
                p.box(0.46,0.66,0.08,0.08,"purple");p.label("BODY",0.47,0.68,0.06);p.label("Systemic loop",0.69,0.64,0.17)
            }
        case "dna":
            p.stage("This reference shows the DNA double helix and the chemical structures of its bases. The sugar-phosphate backbones run along the outside, with bases directed inward.") {p in
                p.line([(0.35,0.28),(0.35,0.72)],"cyan");p.line([(0.65,0.28),(0.65,0.72)],"purple")
                p.label("Sugar–phosphate backbones",0.30,0.23,0.40)
            }
            p.stage("Adenine pairs with thymine through two hydrogen bonds. Cytosine pairs with guanine through three. The order of these bases carries genetic information.") {p in
                for (i,pair) in [("A","T"),("C","G"),("G","C"),("T","A")].enumerated() {
                    let y=0.35+Double(i)*0.10
                    let color=i==0 || i==3 ? "orange":"green"
                    p.box(0.35,y-0.025,0.10,0.05,color);p.box(0.55,y-0.025,0.10,0.05,color)
                    p.label(pair.0,0.37,y-0.017,0.06,color);p.label(pair.1,0.57,y-0.017,0.06,color)
                    let bonds=i==0 || i==3 ? 2:3
                    for j in 0..<bonds {let by=y+(Double(j)-Double(bonds-1)/2)*0.009;p.line([(0.46,by),(0.54,by)],"white")}
                }
            }
        case "client-server":
            p.stage("A browser is a client. It sends a request to a server, commonly using HTTP over an encrypted connection.") {p in
                p.box(0.17,0.38,0.19,0.22,"cyan");p.line([(0.17,0.42),(0.36,0.42)],"cyan");p.label("Browser",0.20,0.47,0.14,"cyan")
                p.box(0.65,0.35,0.17,0.28,"purple");for y in [0.42,0.49,0.56]{p.line([(0.67,y),(0.80,y)],"purple")}
                p.arrow(0.39,0.43,0.23,0,"orange");p.label("1 · Request",0.43,0.37,0.17,"orange")
            }
            p.stage("The server handles the request. It may read or update a database before constructing a response.") {p in
                p.label("Server",0.66,0.66,0.15,"purple");p.label("Validate → process → fetch",0.38,0.27,0.36)
            }
            p.stage("The response travels back to the browser. The client then renders the page or updates the interface.") {p in
                p.arrow(0.62,0.57,-0.23,0,"green");p.label("2 · Response",0.42,0.60,0.19,"green")
            }
        case "binary-tree":
            p.stage("In this binary search tree, each node has at most two children. Smaller keys go left and larger keys go right.") {p in
                for (x,y,dx,dy) in [(0.50,0.34,-0.18,0.16),(0.50,0.34,0.18,0.16),(0.32,0.50,-0.10,0.16),(0.32,0.50,0.10,0.16),(0.68,0.50,-0.10,0.16),(0.68,0.50,0.10,0.16)]{p.line([(x,y),(x+dx,y+dy)],"cyan")}
                for (x,y,n) in [(0.50,0.32,"8"),(0.32,0.48,"3"),(0.68,0.48,"12"),(0.22,0.64,"1"),(0.42,0.64,"6"),(0.58,0.64,"10"),(0.78,0.64,"14")]{p.ellipse(x-0.027,y-0.034,0.054,0.068,"cyan",filled:true);p.label(n,x-0.025,y-0.015,0.05)}
            }
            p.stage("To search, compare your target key with the current node. Choose the left or right subtree according to that comparison, and repeat until the key is found or the path ends.") {p in
                p.arrow(0.48,0.37,-0.13,0.10,"yellow");p.arrow(0.34,0.53,0.06,0.075,"yellow");p.label("Search 6: 8 → 3 → 6",0.34,0.73,0.32,"yellow")
            }
        case "neural-network":
            p.stage("A feedforward neural network takes input features and combines them through weighted connections. This is a small schematic, not a biological brain.") {p in
                for y1 in [0.40,0.60]{for y2 in [0.34,0.50,0.66]{p.line([(0.28,y1),(0.50,y2)],"blue")}}
                p.label("INPUT",0.22,0.26,0.14,"cyan");p.label("HIDDEN",0.45,0.26,0.15,"purple");p.label("OUTPUT",0.68,0.26,0.15,"green")
            }
            p.stage("Hidden units transform weighted sums using activation functions. The next layer combines those activations to produce an output.") {p in
                for y in [0.34,0.50,0.66]{p.line([(0.50,y),(0.74,0.50)],"purple")}
                for y in [0.40,0.60]{p.ellipse(0.255,y-0.035,0.05,0.07,"cyan",filled:true)}
                for y in [0.34,0.50,0.66]{p.ellipse(0.475,y-0.035,0.05,0.07,"purple",filled:true)}
                p.ellipse(0.715,0.465,0.05,0.07,"green",filled:true)
                p.label("Weighted sums + activation",0.32,0.73,0.39)
            }
        case "water-cycle":
            p.stage("The Sun supplies energy that evaporates water from the surface. Water vapor rises into the atmosphere.") {p in
                p.object("sun",0.16,0.27,0.12,0.17);p.line([(0.18,0.68),(0.82,0.68)],"blue");p.label("Surface water",0.19,0.70,0.20,"blue")
                p.arrow(0.32,0.61,0,-0.15,"orange");p.label("Evaporation",0.17,0.47,0.17,"orange")
            }
            p.stage("Cooling vapor condenses into cloud droplets. Droplets can grow and return to the surface as precipitation.") {p in
                p.object("cloud",0.44,0.28,0.20,0.20);p.label("Condensation",0.45,0.25,0.20,"cyan")
                for x in [0.51,0.56,0.61]{p.arrow(x,0.49,0,0.10,"blue")}
                p.label("Precipitation",0.64,0.51,0.18,"blue")
            }
            p.stage("Water returns through runoff and groundwater flow. These paths connect the land, oceans and atmosphere in a continuing cycle.") {p in
                p.line([(0.67,0.67),(0.75,0.56),(0.83,0.67)],"green");p.arrow(0.73,0.64,-0.12,0.025,"green");p.label("Runoff",0.68,0.71,0.13,"green")
            }
        case "solar-system":
            p.stage("The planets orbit the Sun. The inner four planets are Mercury, Venus, Earth and Mars. This layout shows order, not true sizes or orbital distances.") {p in
                p.object("sun",0.13,0.42,0.10,0.16)
                for (i,name) in ["Mercury","Venus","Earth","Mars"].enumerated(){let x=0.28+Double(i)*0.075;p.ellipse(x,0.48,0.02+Double(i%2)*0.008,0.035+Double(i%2)*0.01,i==2 ? "blue":"orange");p.label(name,x-0.025,0.56+Double(i%2)*0.055,0.10)}
            }
            p.stage("Beyond the inner planets come Jupiter, Saturn, Uranus and Neptune. Jupiter and Saturn are gas giants; Uranus and Neptune are ice giants.") {p in
                for (i,name) in ["Jupiter","Saturn","Uranus","Neptune"].enumerated(){let x=0.59+Double(i)*0.065;p.ellipse(x,0.46,0.04,0.07,i<2 ? "yellow":"cyan");p.label(name,x-0.025,0.56+Double(i%2)*0.055,0.11)}
                p.ellipse(0.641,0.478,0.067,0.028,"yellow");p.label("Order and classification · not to scale",0.30,0.71,0.47)
            }
        case "atomic-orbitals":
            p.stage("These are representations of atomic orbitals. The spherical s orbital and differently oriented p orbitals describe wavefunctions, not tiny planetary tracks."){ $0.label("",0.2,0.3) }
            p.stage("The axes distinguish the x, y and z orientations of the p orbitals. Each p orbital has two lobes. Colors are a rendering convention; they do not mean that the lobes carry different electric charges."){ $0.label("",0.2,0.3) }
        case "hybridisation", "hybridisation-sp2":
            p.stage(id=="hybridisation" ? "In the sp cubed model, one s orbital combines with three p orbitals to form four hybrid orbitals." : "In the sp squared model, one s orbital combines with two p orbitals to form three coplanar hybrid orbitals."){ $0.label("",0.2,0.3) }
            p.stage(id=="hybridisation" ? "This is an orbital energy and occupancy schematic. In the sp cubed model the hybrid orbitals can point tetrahedrally. Hybridisation is a bonding model, not a film of orbitals physically mixing." : "The three hybrid directions are trigonal planar. A remaining unhybridised p orbital can participate in pi bonding."){ $0.label("",0.2,0.3) }
        case "neuron":
            p.stage("Dendrites are the branching extensions that receive incoming signals from other neurons."){ $0.label("",0.2,0.3) }
            p.stage("The cell body contains the nucleus and integrates incoming signals."){ $0.label("",0.2,0.3) }
            p.stage("The axon carries signals away from the cell body toward its terminals."){ $0.label("",0.2,0.3) }
            p.stage("Myelin wraps the axon. Gaps called nodes of Ranvier help signals travel rapidly."){ $0.label("",0.2,0.3) }
            p.stage("This enlarged synapse shows how a terminal communicates with another cell using neurotransmitters."){ $0.label("",0.2,0.3) }
        case "digestive-system":
            p.stage("Digestion starts in the mouth, where chewing breaks food down and saliva begins chemical digestion."){ $0.label("",0.2,0.3) }
            p.stage("The oesophagus moves swallowed food toward the stomach."){ $0.label("",0.2,0.3) }
            p.stage("The stomach mixes food with acid and digestive enzymes."){ $0.label("",0.2,0.3) }
            p.stage("The small intestine is the main site of nutrient absorption."){ $0.label("",0.2,0.3) }
            p.stage("The liver produces bile, which supports the digestion of fats."){ $0.label("",0.2,0.3) }
            p.stage("The large intestine absorbs water and processes remaining material before elimination."){ $0.label("",0.2,0.3) }
        default: break
        }
        if DiagramReference.preferredIDs.contains(id) {
            let speeches=p.marks.compactMap(\.speech)
            let marks=ReferenceHighlight.marks(id:id,speeches:speeches)
            return .init(marks:marks,narrate:true,mode:"conceptual",title:entry(id)?.title ?? "Reference diagram",preset:id,figure:id)
        }
        return ScreenDrawing(marks:p.marks,narrate:true,mode:"conceptual",title:entry(id)?.title ?? "Diagram",preset:id)
    }
}
