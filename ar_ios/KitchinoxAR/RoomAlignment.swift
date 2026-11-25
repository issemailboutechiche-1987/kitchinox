// Calage de la cuisine sur la pièce scannée.
// Dans la scène kitchinox, l'origine est le coin des murs A et C : X le long du mur A, Y vers le haut,
// Z (le « y » du plan) vers l'intérieur de la pièce. On cherche donc, dans le scan, un coin où un mur part
// le long de X avec l'intérieur de la pièce du côté +Z. Chaque mur scanné en donne un : on garde celui dont
// les longueurs (mur A, mur suivant) ressemblent le plus aux cotes du projet.

import RoomPlan
import simd

struct CornerFrame {
    var origin: SIMD3<Float> // au sol
    var xAxis: SIMD3<Float> // le long du mur A (horizontal, unitaire)
    var wallLength: Float // longueur du mur A scanné (m)
    var sideLength: Float // longueur du mur qui touche le coin de l'autre côté (m), 0 si inconnu
    var score: Float = 0

    /// Repère monde de la cuisine posée sur ce coin (rotation autour de la verticale seulement).
    var transform: simd_float4x4 {
        let y = SIMD3<Float>(0, 1, 0)
        let z = simd_normalize(simd_cross(xAxis, y))
        return simd_float4x4(columns: (
            SIMD4(xAxis, 0),
            SIMD4(y, 0),
            SIMD4(z, 0),
            SIMD4(origin, 1)
        ))
    }
}

/// Mur scanné ramené au sol : ses deux extrémités.
struct FlatWall {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var length: Float { simd_distance(a, b) }
}

enum RoomAlignment {
    /// Murs du scan, à plat sur le sol.
    static func flatWalls(_ room: CapturedRoom) -> [FlatWall] {
        let floorY = floorHeight(room)
        return room.walls.map { w in
            let t = w.transform
            let c = SIMD3<Float>(t.columns.3.x, floorY, t.columns.3.z)
            var u = SIMD3<Float>(t.columns.0.x, 0, t.columns.0.z)
            u = simd_length(u) > 1e-4 ? simd_normalize(u) : SIMD3(1, 0, 0)
            let h = w.dimensions.x / 2
            return FlatWall(a: c - u * h, b: c + u * h)
        }
    }

    /// Hauteur du sol : le sol scanné, sinon le bas des murs.
    static func floorHeight(_ room: CapturedRoom) -> Float {
        if let f = room.floors.first { return f.transform.columns.3.y }
        let lows = room.walls.map { $0.transform.columns.3.y - $0.dimensions.y / 2 }
        return lows.min() ?? 0
    }

    /// Centre de la pièce (moyenne des milieux des murs), au sol.
    static func center(_ walls: [FlatWall]) -> SIMD3<Float> {
        guard !walls.isEmpty else { return .zero }
        return walls.reduce(SIMD3<Float>.zero) { $0 + ($1.a + $1.b) / 2 } / Float(walls.count)
    }

    /// Tous les coins possibles, du meilleur au moins bon. [project] : largeur et profondeur du projet (mm).
    static func corners(_ room: CapturedRoom, project: SIMD2<Float>?) -> [CornerFrame] {
        let walls = flatWalls(room)
        let mid = center(walls)
        var out: [CornerFrame] = []
        for (i, w) in walls.enumerated() where w.length > 0.3 {
            // l'intérieur doit être du côté +Z = X × Y : sinon on part de l'autre bout
            for (o, e) in [(w.a, w.b), (w.b, w.a)] {
                let x = simd_normalize(e - o)
                let z = simd_cross(x, SIMD3<Float>(0, 1, 0))
                guard simd_dot(z, mid - o) > 0 else { continue }
                // mur voisin qui touche ce coin
                var side: Float = 0
                var best: Float = 0.4
                for (j, v) in walls.enumerated() where j != i {
                    for p in [v.a, v.b] where simd_distance(p, o) < best {
                        best = simd_distance(p, o)
                        side = v.length
                    }
                }
                var c = CornerFrame(origin: o, xAxis: x, wallLength: w.length, sideLength: side)
                if let pr = project {
                    let pw = pr.x / 1000, pd = pr.y / 1000
                    c.score = abs(w.length - pw) + (side > 0 ? abs(side - pd) : pd)
                } else {
                    c.score = -w.length // sans cotes : le plus long mur
                }
                out.append(c)
            }
        }
        return out.sorted { $0.score < $1.score }
    }
}
