extends RefCounted


static func compatible(anchor: PackedByteArray, current: PackedByteArray) -> bool:
	if anchor.is_empty() or anchor.size() != current.size() or anchor.size() % 32 != 0: return false
	for at in range(0, anchor.size(), 32):
		if anchor.slice(at, at + 16) != current.slice(at, at + 16) or anchor.slice(at + 28, at + 32) != current.slice(at + 28, at + 32): return false
		var scale: float = -1.0
		var amax: float = 0.0; var bmax: float = 0.0
		for c in range(3):
			var a: float = anchor.decode_float(at + 16 + c * 4); var b: float = current.decode_float(at + 16 + c * 4)
			if not is_finite(a) or not is_finite(b) or a < 0.0 or b < 0.0: return false
			amax = maxf(amax, a);bmax = maxf(bmax, b)
			if a == 0.0:
				if b != 0.0: return false
			else:
				var ratio: float = b / a
				if scale < 0.0: scale = ratio
				elif absf(scale - ratio) > 2e-06 * maxf(1.0, maxf(scale, ratio)): return false

		if (amax > 0.0 and amax < 1e-05) or (bmax > 0.0 and bmax < 1e-05): return false
	return true
