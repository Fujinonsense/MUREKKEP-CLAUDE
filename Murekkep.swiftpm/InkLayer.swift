import Foundation

/// What the ink layer was drawn for: the view's transform and size, the visible pages and their
/// versions, and the settings the ink shaders read.
struct InkLayerKey: Equatable {
    var originX: Double
    var originY: Double
    var zoom: Double
    var width: Int
    var height: Int
    var pages: [Int]
    var versions: [Int]
    var animate: Bool
    var dry: Double
    var cool: Double
}

/// While the pencil writes, the committed ink of the visible pages is drawn once into a texture and
/// each display frame only lays that texture over the paper and draws the live stroke on top. On a
/// page full of shaded 3D ink this turns every 120 Hz frame from "shade the whole page" into "copy one
/// picture and shade one stroke"; ink that moves (sea, glitter, drying or cooling ink) still redraws
/// the layer at its own rate. The layer holds shadows, inks and grass; highlighters and the live
/// stroke's highlighter and shadow are drawn under it, the live ink over it, which is the order the
/// direct drawing uses.
enum InkLayer {
    /// Whether the layer drawn for `old`, `age` seconds ago, can be shown again for `key` when the
    /// ink in it moves at `contentFPS` (0 = still).
    static func reuse(key: InkLayerKey, old: InkLayerKey?, contentFPS: Int, age: Double) -> Bool {
        guard let old, old == key else { return false }
        guard contentFPS > 0 else { return true }
        return age < 1 / Double(contentFPS)
    }

    /// The layer laid over the frame: one triangle that covers the screen and copies each texel
    /// unfiltered (the layer has the drawable's size, so every pixel lands exactly where it was drawn).
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LayerOut {
        float4 position [[position]];
    };

    vertex LayerOut layer_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1u) & 2u), float(vid & 2u));
        LayerOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    fragment float4 layer_fragment(LayerOut in [[stage_in]],
                                   texture2d<float, access::read> layer [[texture(0)]]) {
        return layer.read(uint2(in.position.xy));
    }
    """
}
