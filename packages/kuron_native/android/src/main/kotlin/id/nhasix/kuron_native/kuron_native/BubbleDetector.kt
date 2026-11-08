package id.nhasix.kuron_native.kuron_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

/**
 * ONNX manga speech-bubble detector — instance segmentation (ShadowB YOLO26s-seg).
 *
 * Input:  1280×1280 RGB float32 CHW [0,1] — letterbox (not stretch)
 * Output0: [1, 300, 38] — [x1,y1,x2,y2, conf, cls_id, m0..m31] (letterbox coords)
 * Output1: [1, 32, 320, 320] — proto masks
 *
 * Mask decode (matches tooling/spike-bubble-seg/seg_fixed.py, FP32 shipping):
 *   coeff(32) · proto[:,y,x] → sigmoid → crop prob to box in proto-space
 *   (×320/1280) → resize to box pixel size (bilinear) → threshold 0.5 →
 *   findContours → largest contour → approxPolyDP → offset to orig → expand 8px.
 *
 * Class: 0=frame (skip), 1=text/thought (include), 2=balloon (include).
 * Returns [shape] (polygon points [[x,y],...] orig coords) and [kind] (class name).
 * shape == null when polygon collapses (< 3 pts) → box fallback.
 */
class BubbleDetector(context: Context) : Closeable {

    // Model lives as a runtime download, NOT an APK asset. Keep in sync
    // with `model.pin.json` "file".
    private var session: ai.onnxruntime.OrtSession? = null
    // Pure-CPU backup session. NNAPI output can silently degrade to garbage on
    // some devices (all confidences below threshold → empty detections), so a
    // zero-result NNAPI run is re-run on CPU before giving up.
    private var cpuSession: ai.onnxruntime.OrtSession? = null
    private val env: ai.onnxruntime.OrtEnvironment
    private val inputName: String
    private val modelInputSize: Int = 1280
    private val protoSize: Int = 320

    // Thresholds / pipeline constants (mirror seg_fixed.py)
    private val confThreshold = 0.25f
    // Narration/thought boxes (cls 1) often score 0.15–0.24; balloon (cls 2) stays strict.
    private val confThresholdText = 0.15f
    private val maskThreshold = 0.5f
    private val polyEpsilonFrac = 0.015f   // approxPolyDP: fraction of arc length
    private val renderPad = 3              // outward expand polygon (orig px)
    private val minBoxDim = 4f

    // Letterbox state
    private var padLeft: Int = 0
    private var padTop: Int = 0
    private var letterScale: Float = 1f

    // Preferred EP: NNAPI delegates to the device GPU/NPU/driver (API 27+;
    // ORT falls back to CPU automatically below the min feature level). Stock
    // ORT Android ships no OpenCL/Vulkan EP — NNAPI IS the hardware path.
    // Falls back to CPU when init fails (spec: silent fallback, no error).
    private var usesNnapi = false

    init {
        env = ai.onnxruntime.OrtEnvironment.getEnvironment()
        val file = modelFile(context)
        // Model is a runtime download, NOT an APK asset: absent/corrupt file
        // means "not downloaded" — detection falls back to full-image, no crash.
        val modelBytes = if (file.exists()) file.readBytes() else null
        if (modelBytes == null) {
            android.util.Log.w(TAG, "Model not downloaded (${file.absolutePath}) — detection unavailable")
            inputName = ""
        } else {
        // NNAPI session build can THROW even when addNnapi() succeeds — the
        // model contains ops NNAPI lacks a kernel for (e.g. Flatten on
        // MediaTek shims: "Failed to find kernel ... Kernel not found").
        // When that happens, fall straight to a pure-CPU session instead of
        // leaving session == null and failing every detect call.
        val nnapiSession: ai.onnxruntime.OrtSession? = try {
            val opts = ai.onnxruntime.OrtSession.SessionOptions()
            opts.addNnapi()
            opts.addCPU(true)
            env.createSession(modelBytes, opts)
        } catch (e: Exception) {
            android.util.Log.w(TAG, "NNAPI session failed (${e.message}) — using CPU only")
            null
        }

        if (nnapiSession != null) {
            usesNnapi = true
            session = nnapiSession
            // Pure-CPU backup: used when NNAPI fails at run() time or returns
            // garbage (zero detections) — see detect().
            val cpuOptions = ai.onnxruntime.OrtSession.SessionOptions()
            cpuOptions.addCPU(true)
            cpuSession = env.createSession(modelBytes, cpuOptions)
            android.util.Log.i(TAG, "BubbleDetector loaded (seg, nnapi=true, cpuBackup=true)")
        } else {
            val cpuOptions = ai.onnxruntime.OrtSession.SessionOptions()
            cpuOptions.addCPU(true)
            session = env.createSession(modelBytes, cpuOptions)
            android.util.Log.i(TAG, "BubbleDetector loaded (seg, nnapi=false, cpu-only)")
        }
        val inputNames = session?.inputNames ?: throw RuntimeException("No input names")
        inputName = inputNames.iterator().next()
        }
    }

    /**
     * Detect bubbles. Returns list of maps:
     *   "x","y","w","h" (orig pixel), "confidence" (Double),
     *   "kind" (String: "balloon"/"text"/"frame"/"unknown"),
     *   "shape" (List<List<Int>>? [[x,y],...] orig coords; null on box fallback).
     */
    fun detect(imageBytes: ByteArray, origWidth: Int, origHeight: Int): List<Map<String, Any>> {
        // 1. Letterbox prep (shared between EP attempts — expensive, do once)
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size) ?: return emptyList()
        val scale = minOf(modelInputSize.toFloat() / bitmap.width, modelInputSize.toFloat() / bitmap.height)
        val newW = (bitmap.width * scale).toInt()
        val newH = (bitmap.height * scale).toInt()
        padLeft = (modelInputSize - newW) / 2
        padTop = (modelInputSize - newH) / 2
        letterScale = scale

        val resized = Bitmap.createScaledBitmap(bitmap, newW, newH, true)
        val letterbox = Bitmap.createBitmap(modelInputSize, modelInputSize, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(letterbox)
        canvas.drawBitmap(resized, padLeft.toFloat(), padTop.toFloat(), null)
        resized.recycle()
        val floatBuf = preprocessToBuffer(letterbox)
        letterbox.recycle()
        bitmap.recycle()

        // 2. Inference — primary EP first, CPU backup on ANY failure/empty output.
        // NNAPI can throw at run() time (unsupported op kernel, e.g. Flatten
        // on MediaTek shims) even when addNnapi() succeeded — the session
        // initializes but execution fails. The CPU session must catch both.
        val sess = session ?: return emptyList()
        var primary: List<Map<String, Any>>? = null
        var primaryError: String? = null
        try {
            primary = runInference(sess, floatBuf, origWidth, origHeight, scale, "nnapi")
        } catch (e: Exception) {
            primaryError = e.message
            android.util.Log.w(TAG, "NNAPI inference failed: ${e.message}")
        }
        val fallbackToCpu = cpuSession != null && (primary == null || primary.isEmpty())
        if (fallbackToCpu) {
            val why = if (primaryError != null) "failed ($primaryError)" else "returned 0 detections"
            android.util.Log.w(TAG, "NNAPI $why — retrying on CPU")
            floatBuf.rewind() // runInference consumed the buffer position
            return runInference(cpuSession!!, floatBuf, origWidth, origHeight, scale, "cpu")
        }
        return primary ?: emptyList()
    }

    /** Runs one inference pass and decodes detections. [epLabel] for logging. */
    private fun runInference(
        sess: ai.onnxruntime.OrtSession,
        floatBuf: FloatBuffer,
        origWidth: Int,
        origHeight: Int,
        scale: Float,
        epLabel: String,
    ): List<Map<String, Any>> {
        val shape = longArrayOf(1L, 3L, modelInputSize.toLong(), modelInputSize.toLong())
        val inputOnnx = ai.onnxruntime.OnnxTensor.createTensor(env, floatBuf, shape)
        val results = sess.run(mapOf(inputName to inputOnnx))
        inputOnnx.close()

        try {
            val out0 = results[0] as? ai.onnxruntime.OnnxTensor ?: return emptyList()
            val out1 = results[1] as? ai.onnxruntime.OnnxTensor ?: return emptyList()
            val detBuf = out0.floatBuffer
            val protoBuf = out1.floatBuffer
            val valuesPerRow = 38
            val numDet = 300

            val detections = mutableListOf<Map<String, Any>>()

            for (i in 0 until numDet) {
                val base = i * valuesPerRow
                val x1 = detBuf.get(base)
                val y1 = detBuf.get(base + 1)
                val x2 = detBuf.get(base + 2)
                val y2 = detBuf.get(base + 3)
                val conf = detBuf.get(base + 4)
                val clsId = detBuf.get(base + 5).toInt()

                val minConf = if (clsId == 1) confThresholdText else confThreshold
                if (conf < minConf) continue
                if (x2 - x1 < minBoxDim || y2 - y1 < minBoxDim) continue

                val coeff = FloatArray(32) { c -> detBuf.get(base + 6 + c) }

                // Decode mask to letterbox-box-local binary (bw×bh)
                val mask = decodeMask(coeff, protoBuf, x1, y1, x2, y2) ?: continue

                // Polygon in letterbox space, then → orig, then expand
                val polyLb = maskToPolygonLb(mask.binary, mask.bw, mask.bh, x1, y1)
                val shapePts: List<List<Int>>? = if (polyLb != null && polyLb.size >= 3) {
                    lbToOrig(polyLb, origWidth, origHeight)
                        ?.let { expandPolygon(it, origWidth, origHeight) }
                } else null

                // Box in orig coords
                val bx1 = ((x1 - padLeft) / scale).toInt().coerceIn(0, origWidth - 1)
                val by1 = ((y1 - padTop) / scale).toInt().coerceIn(0, origHeight - 1)
                val bx2 = ((x2 - padLeft) / scale).toInt().coerceIn(0, origWidth - 1)
                val by2 = ((y2 - padTop) / scale).toInt().coerceIn(0, origHeight - 1)
                val rw = (bx2 - bx1).coerceAtLeast(1)
                val rh = (by2 - by1).coerceAtLeast(1)

                val map = mutableMapOf<String, Any>(
                    "x" to bx1,
                    "y" to by1,
                    "w" to rw,
                    "h" to rh,
                    "confidence" to conf.toDouble(),
                    "kind" to kindOf(clsId),
                )
                if (shapePts != null) map["shape"] = shapePts
                detections.add(map)
            }

            if (detections.isEmpty()) {
                android.util.Log.w(TAG, "Inference ($epLabel): 0 detections above threshold")
            }
            return detections
        } finally {
            results.close()
        }
    }

    private class DecodedMask(val binary: BooleanArray, val bw: Int, val bh: Int)

    /** coeff(32) · proto[:,y,x] → sigmoid → crop to box (proto-space) → resize to box → threshold. */
    private fun decodeMask(
        coeff: FloatArray,
        protoBuf: FloatBuffer,
        x1: Float, y1: Float, x2: Float, y2: Float,
    ): DecodedMask? {
        val s = protoSize.toFloat() / modelInputSize.toFloat()
        val px1 = (x1 * s).toInt().coerceIn(0, protoSize - 1)
        val py1 = (y1 * s).toInt().coerceIn(0, protoSize - 1)
        val px2 = (x2 * s).toInt().coerceIn(0, protoSize)
        val py2 = (y2 * s).toInt().coerceIn(0, protoSize)
        if (px2 - px1 < 1 || py2 - py1 < 1) return null
        val cropW = px2 - px1
        val cropH = py2 - py1

        // sigmoid(coeff · proto) for each crop pixel
        val prob = FloatArray(cropW * cropH)
        for (y in 0 until cropH) {
            for (x in 0 until cropW) {
                var v = 0f
                val py = py1 + y
                val px = px1 + x
                for (c in 0 until 32) {
                    v += coeff[c] * protoBuf.get(c * protoSize * protoSize + py * protoSize + px)
                }
                prob[y * cropW + x] = sigmoid(v)
            }
        }

        // resize to box pixel size (bilinear), threshold
        val bw = (x2 - x1).toInt().coerceAtLeast(1)
        val bh = (y2 - y1).toInt().coerceAtLeast(1)
        val resized = resizeBilinear(prob, cropW, cropH, bw, bh)
        val binary = BooleanArray(bw * bh)
        for (idx in resized.indices) binary[idx] = resized[idx] >= maskThreshold
        return DecodedMask(binary, bw, bh)
    }

    private fun sigmoid(v: Float): Float {
        val z = v.coerceIn(-80f, 80f)
        return 1f / (1f + exp(-z))
    }

    /** Bilinear resize (matches cv2.INTER_LINEAR). */
    private fun resizeBilinear(src: FloatArray, sw: Int, sh: Int, dw: Int, dh: Int): FloatArray {
        val dst = FloatArray(dw * dh)
        val xRatio = if (dw > 1) sw.toDouble() / dw else 0.0
        val yRatio = if (dh > 1) sh.toDouble() / dh else 0.0
        for (y in 0 until dh) {
            val sy = y * yRatio
            val y0 = sy.toInt().coerceIn(0, sh - 1)
            val fy = (sy - y0).toFloat().coerceIn(0f, 1f)
            val y1 = min(y0 + 1, sh - 1)
            for (x in 0 until dw) {
                val sx = x * xRatio
                val x0 = sx.toInt().coerceIn(0, sw - 1)
                val fx = (sx - x0).toFloat().coerceIn(0f, 1f)
                val x1 = min(x0 + 1, sw - 1)
                val p00 = src[y0 * sw + x0]
                val p10 = src[y0 * sw + x1]
                val p01 = src[y1 * sw + x0]
                val p11 = src[y1 * sw + x1]
                val top = p00 + (p10 - p00) * fx
                val bot = p01 + (p11 - p01) * fx
                dst[y * dw + x] = top + (bot - top) * fy
            }
        }
        return dst
    }

    /**
     * Outer contour of binary mask (box-local coords) → simplify → offset to
     * letterbox space. Mirrors cv2.findContours(RETR_EXTERNAL) + approxPolyDP.
     */
    private fun maskToPolygonLb(binary: BooleanArray, w: Int, h: Int, boxX1: Float, boxY1: Float): List<Pair<Float, Float>>? {
        val contour = traceOuterContour(binary, w, h) ?: return null
        if (contour.size < 3) return null

        // Closed ring (repeat first point at end) for approxPolyDP
        val ring = ArrayList<IntArray>(contour.size + 1)
        ring.addAll(contour)
        ring.add(contour[0])

        val simplified = approxPolyDP(ring, polyEpsilonFrac)
        if (simplified.size < 3) return null
        return simplified.map { Pair(boxX1 + it[0], boxY1 + it[1]) }
    }

    /** Is mask pixel on the boundary (any 4-neighbor is background/box edge)? */
    private fun isEdge(binary: BooleanArray, w: Int, h: Int, x: Int, y: Int): Boolean {
        return x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
            !binary[y * w + (x - 1)] || !binary[y * w + (x + 1)] ||
            !binary[(y - 1) * w + x] || !binary[(y + 1) * w + x]
    }

    /**
     * Moore-neighbor boundary tracing of the outer contour (topmost-leftmost
     * start, clockwise). Mirrors cv2.findContours outer boundary for a filled
     * blob. Returns ordered boundary pixels (no closing repeat).
     */
    private fun traceOuterContour(binary: BooleanArray, w: Int, h: Int): List<IntArray>? {
        // start: topmost-leftmost boundary pixel
        var start: IntArray? = null
        outer@ for (y in 0 until h) {
            for (x in 0 until w) {
                if (binary[y * w + x] && isEdge(binary, w, h, x, y)) {
                    start = intArrayOf(x, y); break@outer
                }
            }
        }
        val s = start ?: return null

        // 8-neighbor offsets, clockwise: 0=E,1=SE,2=S,3=SW,4=W,5=NW,6=N,7=NE
        val dx = intArrayOf(1, 1, 0, -1, -1, -1, 0, 1)
        val dy = intArrayOf(0, 1, 1, 1, 0, -1, -1, -1)

        val path = ArrayList<IntArray>()
        path.add(s)
        var cur = s
        var dir = 7 // begin scan from NE so we step onto the contour edge
        val maxIter = w * h * 4
        var guard = 0
        while (true) {
            if (++guard > maxIter) break
            var found = false
            for (k in 0 until 8) {
                val nd = (dir + 1 + k) % 8
                val nx = cur[0] + dx[nd]
                val ny = cur[1] + dy[nd]
                if (nx in 0 until w && ny in 0 until h && binary[ny * w + nx] && isEdge(binary, w, h, nx, ny)) {
                    cur = intArrayOf(nx, ny)
                    path.add(cur)
                    dir = (nd + 4) % 8 // backtrack: next scan starts from entry direction
                    found = true
                    break
                }
            }
            if (!found) break
            if (cur[0] == s[0] && cur[1] == s[1]) break // closed loop
        }
        // drop the closing duplicate start we may have appended
        if (path.size >= 2 && path.first().contentEquals(path.last())) {
            path.removeAt(path.size - 1)
        }
        return if (path.size < 3) null else path
    }

    /** Ramer–Douglas–Peucker on a closed ring; return simplified points (no repeat). */
    private fun approxPolyDP(ring: List<IntArray>, epsilonFrac: Float): List<IntArray> {
        // compute perimeter
        var perim = 0f
        for (i in 0 until ring.size - 1) {
            perim += dist(ring[i], ring[i + 1])
        }
        val eps = epsilonFrac * perim

        // RDP
        val keep = BooleanArray(ring.size) { false }
        keep[0] = true
        keep[ring.size - 1] = true
        rdp(ring, 0, ring.size - 1, keep, eps)
        val result = ArrayList<IntArray>()
        for (i in 0 until ring.size) if (keep[i]) result.add(ring[i])
        // drop the closing duplicate
        if (result.size >= 2 &&
            result.first().contentEquals(result.last())) {
            result.removeAt(result.size - 1)
        }
        return result
    }

    private fun rdp(ring: List<IntArray>, first: Int, last: Int, keep: BooleanArray, eps: Float) {
        if (last <= first + 1) return
        var maxDist = 0f
        var index = first
        for (i in (first + 1) until last) {
            val d = perpDist(ring[i], ring[first], ring[last])
            if (d > maxDist) { maxDist = d; index = i }
        }
        if (maxDist > eps) {
            keep[index] = true
            rdp(ring, first, index, keep, eps)
            rdp(ring, index, last, keep, eps)
        }
    }

    private fun dist(a: IntArray, b: IntArray): Float {
        val dx = a[0] - b[0]; val dy = a[1] - b[1]
        return Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
    }

    private fun perpDist(p: IntArray, a: IntArray, b: IntArray): Float {
        val vx = b[0] - a[0]; val vy = b[1] - a[1]
        val len = Math.sqrt((vx * vx + vy * vy).toDouble())
        if (len < 1e-6) return dist(p, a)
        // distance from p to line ab
        val cross = Math.abs(((b[0] - a[0]) * (a[1] - p[1]) - (a[0] - p[0]) * (b[1] - a[1])).toDouble())
        return (cross / len).toFloat()
    }

    /** Letterbox → orig coords, clipped. */
    private fun lbToOrig(pts: List<Pair<Float, Float>>, ow: Int, oh: Int): List<FloatArray>? {
        val out = ArrayList<FloatArray>(pts.size)
        for ((x, y) in pts) {
            val ox = ((x - padLeft) / letterScale).coerceIn(0f, ow - 1f)
            val oy = ((y - padTop) / letterScale).coerceIn(0f, oh - 1f)
            out.add(floatArrayOf(ox, oy))
        }
        return out
    }

    /** Expand polygon outward by [renderPad] px (centroid-based), clipped. */
    private fun expandPolygon(pts: List<FloatArray>, ow: Int, oh: Int): List<List<Int>> {
        var cx = 0f; var cy = 0f
        for (p in pts) { cx += p[0]; cy += p[1] }
        cx /= pts.size; cy /= pts.size
        return pts.map { p ->
            val dx = p[0] - cx; val dy = p[1] - cy
            val norm = Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
            val nx = if (norm < 1e-6) 0f else dx / norm * renderPad
            val ny = if (norm < 1e-6) 0f else dy / norm * renderPad
            val ex = (p[0] + nx).toInt().coerceIn(0, ow - 1)
            val ey = (p[1] + ny).toInt().coerceIn(0, oh - 1)
            listOf(ex, ey)
        }
    }

    private fun kindOf(clsId: Int): String = when (clsId) {
        2 -> "balloon"
        1 -> "text"
        0 -> "frame"
        else -> "unknown"
    }

    /** ARGB → float32 CHW [0,1], sequential put. */
    private fun preprocessToBuffer(bitmap: Bitmap): FloatBuffer {
        val pixels = IntArray(modelInputSize * modelInputSize)
        bitmap.getPixels(pixels, 0, modelInputSize, 0, 0, modelInputSize, modelInputSize)
        val total = 3 * modelInputSize * modelInputSize

        val floatBuffer = ByteBuffer.allocateDirect(total * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        for (y in 0 until modelInputSize) {
            for (x in 0 until modelInputSize) {
                val pixel = pixels[y * modelInputSize + x]
                floatBuffer.put(((pixel shr 16) and 0xFF) / 255.0f) // R
            }
        }
        for (y in 0 until modelInputSize) {
            for (x in 0 until modelInputSize) {
                val pixel = pixels[y * modelInputSize + x]
                floatBuffer.put(((pixel shr 8) and 0xFF) / 255.0f)  // G
            }
        }
        for (y in 0 until modelInputSize) {
            for (x in 0 until modelInputSize) {
                val pixel = pixels[y * modelInputSize + x]
                floatBuffer.put((pixel and 0xFF) / 255.0f)           // B
            }
        }

        floatBuffer.flip()
        return floatBuffer
    }

    override fun close() {
        try { cpuSession?.close() } catch (_: Exception) {}
        try { session?.close() } catch (_: Exception) {}
    }

    companion object {
        const val TAG = "BubbleDetector"
        const val MODEL_FILE_NAME = "bubble_detector.onnx"
        private const val MODELS_SUBDIR = "models"

        /** Final model path. */
        fun modelFile(context: Context): java.io.File =
            java.io.File(java.io.File(context.filesDir, MODELS_SUBDIR), MODEL_FILE_NAME)

        fun partFile(context: Context): java.io.File =
            java.io.File(java.io.File(context.filesDir, MODELS_SUBDIR), "$MODEL_FILE_NAME.part")
    }
}