import SwiftUI

struct FloatingSolutionView:View {
    let drawing:ScreenDrawing
    let visibleCount:Int
    let complete:Bool
    let accent:Color
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8){Image(systemName:complete ? "checkmark.circle.fill":"sparkles").foregroundStyle(accent);Text(complete ? "Solution":"Let's work through it").font(.system(size:14,weight:.semibold));Spacer();Text("\(min(visibleCount,drawing.marks.count))/\(drawing.marks.count)").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)}
            Divider().overlay(accent.opacity(0.15))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        ForEach(Array(drawing.marks.prefix(visibleCount).enumerated()),id:\.offset){index,mark in
                            HStack(alignment:.top,spacing:10) {
                                Text(String(index+1)).font(.system(size:11,weight:.semibold)).foregroundStyle(accent).frame(width:22,height:22).background(accent.opacity(0.12),in:Circle())
                                FormattedResponse(text:mark.text ?? "",fontSize:14).frame(maxWidth:.infinity,alignment:.leading)
                            }.id(index).transition(.opacity.combined(with:.move(edge:.bottom)))
                        }
                    }
                }.onChange(of:visibleCount){_,value in withAnimation(.easeInOut(duration:0.25)){proxy.scrollTo(max(0,value-1),anchor:.bottom)}}
            }
        }.padding(16).background(RoundedRectangle(cornerRadius:16).fill(Color(red:0.075,green:0.085,blue:0.08).opacity(0.98)))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(accent.opacity(0.28),lineWidth:1))
            .shadow(color:.black.opacity(0.20),radius:12,y:5)
            .animation(.easeInOut(duration:0.25),value:visibleCount)
    }
}
