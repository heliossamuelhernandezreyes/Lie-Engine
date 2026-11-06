"""Source-only quadrature and comparisons; no LIE transport equations here."""
import numpy as np


def split_triangle(vertices, maximum_edge=.075, minimum_area=0.):
    """Bisect the longest edge, with an explicit thin-triangle stopping budget.

    Area remains exact. A positive minimum_area allows long thin bevel/box-side
    triangles to stay coarse instead of exhausting the common field capacity.
    """
    pending = [np.asarray(vertices, dtype=float)]
    output = []
    while pending:
        t = pending.pop()
        lengths = [np.linalg.norm(t[(k+1) % 3]-t[k]) for k in range(3)]
        k = int(np.argmax(lengths))
        if lengths[k] <= maximum_edge or triangle_area(t) <= minimum_area:
            output.append(t)
            continue
        a, b, c = t[k], t[(k+1) % 3], t[(k+2) % 3]
        m = (a+b)*.5
        pending.extend((np.array([a, m, c]), np.array([m, b, c])))
    return output


def triangle_area(t):
    return float(np.linalg.norm(np.cross(t[1]-t[0], t[2]-t[0]))*.5)


def camera_frame(eye, target):
    forward = np.asarray(target, float)-eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0., 1., 0.])
    right /= np.linalg.norm(right)
    return right, np.cross(right, forward), forward


def metrics(actual, reference, mask=None):
    """Linear RGB errors with an explicit, fixed support; no per-image fitting."""
    a, b = np.asarray(actual, float), np.asarray(reference, float)
    if a.shape != b.shape or a.ndim != 3 or a.shape[-1] != 3:
        raise ValueError('RGB shape mismatch')
    if not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('Nonfinite radiance')
    selected = np.ones(a.shape[:2], bool) if mask is None else np.asarray(mask, bool)
    if selected.shape != a.shape[:2] or not selected.any():
        raise ValueError('Empty or invalid comparison mask')
    x, y = a[selected], b[selected]
    error = x-y
    return {'pixels': int(selected.sum()), 'mae': float(np.mean(abs(error))),
            'rmse': float(np.sqrt(np.mean(error*error))),
            'relative_l1': float(np.sum(abs(error))/max(np.sum(abs(y)), 1e-12)),
            'reference_mean_rgb': y.mean(0).tolist(), 'actual_mean_rgb': x.mean(0).tolist(),
            'mean_signed_error_rgb': error.mean(0).tolist(),
            'max_absolute': float(np.max(abs(error)))}


def preview(linear, exposure=1.):
    x = np.maximum(np.asarray(linear, float)*exposure, 0.)
    x /= 1+x
    x = np.where(x <= .0031308, x*12.92, 1.055*x**(1/2.4)-.055)
    return np.uint8(np.clip(np.rint(x*255), 0, 255))
