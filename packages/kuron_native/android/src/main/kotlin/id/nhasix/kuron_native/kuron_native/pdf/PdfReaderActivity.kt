package id.nhasix.kuron_native.kuron_native.pdf

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.LruCache
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import id.nhasix.kuron_native.kuron_native.R
import kotlinx.coroutines.*
import java.io.File
import java.util.Collections

/**
 * Vertical Continuous Scroll PDF Viewer (Webtoon Style)
 * Uses RecyclerView for 120Hz smooth scrolling and memory efficiency.
 */
class PdfReaderActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_PDF_PATH = "pdf_path"
        const val EXTRA_PDF_TITLE = "pdf_title"
        const val EXTRA_START_PAGE = "start_page"

        const val EXTRA_BACKGROUND_COLOR = "background_color"
        const val EXTRA_TEXT_COLOR = "text_color"

        fun createIntent(activity: Activity, pdfPath: String, title: String = "", startPage: Int = 0, backgroundColor: String? = null, textColor: String? = null): Intent {
            return Intent(activity, PdfReaderActivity::class.java).apply {
                putExtra(EXTRA_PDF_PATH, pdfPath)
                putExtra(EXTRA_PDF_TITLE, title)
                putExtra(EXTRA_START_PAGE, startPage)
                putExtra(EXTRA_BACKGROUND_COLOR, backgroundColor)
                putExtra(EXTRA_TEXT_COLOR, textColor)
            }
        }

        // Overload for Context (needed for Plugin usage)
        fun createIntent(context: android.content.Context, pdfPath: String, title: String = "", startPage: Int = 0, backgroundColor: String? = null, textColor: String? = null): Intent {
            return Intent(context, PdfReaderActivity::class.java).apply {
                putExtra(EXTRA_PDF_PATH, pdfPath)
                putExtra(EXTRA_PDF_TITLE, title)
                putExtra(EXTRA_START_PAGE, startPage)
                putExtra(EXTRA_BACKGROUND_COLOR, backgroundColor)
                putExtra(EXTRA_TEXT_COLOR, textColor)
            }
        }
    }

    private lateinit var recyclerView: RecyclerView
    private lateinit var toolbar: com.google.android.material.appbar.MaterialToolbar
    private lateinit var appBarLayout: com.google.android.material.appbar.AppBarLayout
    private lateinit var pageIndicator: TextView
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var btnToggleMode: android.widget.ImageButton

    private var pdfRenderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var totalPages = 0
    private var adapter: PdfPageAdapter? = null

    private var isVerticalMode = true // Default to Vertical (Webtoon)
    private var isControlsVisible = true

    // Coroutine scope for async rendering
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enable Edge-to-Edge
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        setContentView(R.layout.activity_pdf_reader)

        // Initialize Views
        recyclerView = findViewById(R.id.pdfRecyclerView)
        toolbar = findViewById(R.id.toolbar)
        appBarLayout = findViewById(R.id.appBarLayout)
        pageIndicator = findViewById(R.id.pageIndicator)
        loadingIndicator = findViewById(R.id.loadingIndicator)
        btnToggleMode = findViewById(R.id.btnToggleMode)

        val pdfPath = intent?.getStringExtra(EXTRA_PDF_PATH)
        val title = intent?.getStringExtra(EXTRA_PDF_TITLE) ?: "PDF Document"
        val startPage = intent?.getIntExtra(EXTRA_START_PAGE, 0) ?: 0

        if (pdfPath == null) {
            finish()
            return
        }

        // Setup Toolbar
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.setDisplayShowHomeEnabled(true)
        toolbar.title = title
        toolbar.setNavigationOnClickListener {
            finish()
        }

        applyThemeColors()

        btnToggleMode.setOnClickListener {
            toggleReadingMode()
        }
        
        openPdf(pdfPath, startPage)
    }

    private fun applyThemeColors() {
        val bgColorHex = intent?.getStringExtra(EXTRA_BACKGROUND_COLOR)
        val txtColorHex = intent?.getStringExtra(EXTRA_TEXT_COLOR)

        if (bgColorHex != null) {
            try {
                val parsedBgColor = Color.parseColor(bgColorHex)
                findViewById<View>(android.R.id.content).setBackgroundColor(parsedBgColor)
                appBarLayout.setBackgroundColor(parsedBgColor)
                toolbar.setBackgroundColor(parsedBgColor)
                recyclerView.setBackgroundColor(parsedBgColor)
                
                // Adjust status bar text color based on luminance
                val luminance = (0.299 * Color.red(parsedBgColor) + 0.587 * Color.green(parsedBgColor) + 0.114 * Color.blue(parsedBgColor)) / 255
                val isLight = luminance > 0.5
                WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = isLight
            } catch (e: Exception) {
                // Ignore parsing errors, keep default theme
            }
        }

        if (txtColorHex != null) {
            try {
                val parsedTxtColor = Color.parseColor(txtColorHex)
                toolbar.setTitleTextColor(parsedTxtColor)
                pageIndicator.setTextColor(parsedTxtColor)
                btnToggleMode.setColorFilter(parsedTxtColor)
                
                // Color back button and overflow icons
                toolbar.navigationIcon?.mutate()?.setTint(parsedTxtColor)
                toolbar.overflowIcon?.mutate()?.setTint(parsedTxtColor)
            } catch (e: Exception) {
                // Ignore parsing errors
            }
        }
    }

    private fun openPdf(path: String, startPage: Int) {
        scope.launch(Dispatchers.IO) {
            try {
                val file = File(path)
                if (!file.exists()) {
                    withContext(Dispatchers.Main) { finish() }
                    return@launch
                }

                fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                val renderer = PdfRenderer(fileDescriptor!!)
                pdfRenderer = renderer
                totalPages = renderer.pageCount

                val screenWidth = resources.displayMetrics.widthPixels.coerceAtLeast(1)
                val heights = IntArray(totalPages)
                synchronized(renderer) {
                    for (i in 0 until totalPages) {
                        renderer.openPage(i).use { page ->
                            val srcW = page.width.coerceAtLeast(1)
                            heights[i] =
                                (page.height * (screenWidth.toFloat() / srcW)).toInt().coerceAtLeast(1)
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    setupRecyclerView(startPage, heights)
                    updatePageIndicator(startPage)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) { finish() }
            }
        }
    }

    private fun setupRecyclerView(startPage: Int, pageHeights: IntArray) {
        adapter = PdfPageAdapter(pdfRenderer!!, totalPages, pageHeights) {
            toggleControls()
        }
        recyclerView.adapter = adapter
        recyclerView.setHasFixedSize(true)
        recyclerView.setItemViewCacheSize(5)

        applyLayoutManager(startPage)

        // Scroll Listener for Indicator
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
                val pos = layoutManager?.let {
                    val complete = it.findFirstCompletelyVisibleItemPosition()
                    if (complete != RecyclerView.NO_POSITION) complete
                    else it.findFirstVisibleItemPosition()
                } ?: RecyclerView.NO_POSITION
                if (pos != RecyclerView.NO_POSITION) {
                    updatePageIndicator(pos)
                }
            }
        })
    }

    private var snapHelper: androidx.recyclerview.widget.SnapHelper? = null

    private fun applyLayoutManager(targetPage: Int) {
        val layoutManager = LinearLayoutManager(this)
        layoutManager.orientation = if (isVerticalMode) RecyclerView.VERTICAL else RecyclerView.HORIZONTAL
        recyclerView.layoutManager = layoutManager
        
        // Remove existing SnapHelper
        snapHelper?.attachToRecyclerView(null)
        snapHelper = null
        recyclerView.onFlingListener = null // Ensure FlingListener is cleared
        
        if (!isVerticalMode) {
            // Horizontal Mode: Snap to pages
            snapHelper = androidx.recyclerview.widget.PagerSnapHelper()
            snapHelper?.attachToRecyclerView(recyclerView)
            
            // Icon: Rotate to indicate horizontal
            btnToggleMode.rotation = 90f 
        } else {
             // Vertical Mode: Default
             btnToggleMode.rotation = 0f
        }

        // Restore position
        if (targetPage >= 0) {
            recyclerView.scrollToPosition(targetPage)
        }
    }

    private fun toggleReadingMode() {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
        val currentPage = layoutManager?.findFirstVisibleItemPosition() ?: 0
        
        // Reset zoom on all visible items before mode change
        resetAllZoom()
        
        isVerticalMode = !isVerticalMode
        applyLayoutManager(currentPage)
        // Notify adapter to rebind views with correct layout params
        adapter?.notifyDataSetChanged()
    }
    
    private fun resetAllZoom() {
        // Reset zoom on all currently visible ViewHolders
        for (i in 0 until recyclerView.childCount) {
            val view = recyclerView.getChildAt(i)
            if (view is ZoomableImageView) {
                view.resetZoom()
            }
        }
    }

    private fun toggleControls() {
        isControlsVisible = !isControlsVisible
        val visibility = if (isControlsVisible) View.VISIBLE else View.GONE
        appBarLayout.visibility = visibility
        pageIndicator.visibility = visibility
    }

    private fun updatePageIndicator(pageIndex: Int) {
        pageIndicator.text = "${pageIndex + 1} / $totalPages"
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel() // Cancel all pending rendering jobs
        try {
            pdfRenderer?.close()
            fileDescriptor?.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // --- Adapter ---

    inner class PdfPageAdapter(
        private val renderer: PdfRenderer,
        private val count: Int,
        private val pageHeights: IntArray,
        private val onItemClick: () -> Unit
    ) : RecyclerView.Adapter<PdfPageViewHolder>() {

        private val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        private val cacheSize = maxMemory / 4
        private val memoryCache = object : LruCache<Int, Bitmap>(cacheSize) {
            override fun sizeOf(key: Int, bitmap: Bitmap): Int {
                return bitmap.byteCount / 1024
            }
        }
        private val inFlightPrefetch = Collections.synchronizedSet(mutableSetOf<Int>())

        init {
            setHasStableIds(true)
        }

        override fun getItemId(position: Int): Long = position.toLong()

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PdfPageViewHolder {
            val imageView = ZoomableImageView(parent.context).apply {
                // Don't override scaleType - ZoomableImageView sets it to MATRIX in init
                adjustViewBounds = false  // Disable to allow zoom/pan
            }
            return PdfPageViewHolder(imageView)
        }

        override fun onBindViewHolder(holder: PdfPageViewHolder, position: Int) {
            holder.renderJob?.cancel()
            holder.renderJob = null
            holder.currentPosition = position
            holder.imageView.resetZoom()

            holder.imageView.layoutParams = if (isVerticalMode) {
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    pageHeights.getOrElse(position) { ViewGroup.LayoutParams.WRAP_CONTENT }
                )
            } else {
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }

            holder.imageView.setOnClickListener { onItemClick() }

            val cachedBitmap = memoryCache.get(position)

            if (cachedBitmap != null) {
                holder.imageView.setImageBitmap(cachedBitmap)
                holder.imageView.background = null
                prefetchAdjacent(position)
            } else {
                holder.imageView.setImageBitmap(null)
                holder.imageView.setBackgroundColor(0xFF222222.toInt())
                holder.renderJob = renderPageAsync(position, holder)
                prefetchAdjacent(position)
            }
        }

        override fun onViewRecycled(holder: PdfPageViewHolder) {
            holder.renderJob?.cancel()
            holder.renderJob = null
            holder.currentPosition = -1
            super.onViewRecycled(holder)
        }

        private fun prefetchAdjacent(position: Int) {
            val targets = listOf(position + 1, position + 2)
            for (idx in targets) {
                if (idx !in 0 until count) continue
                if (memoryCache.get(idx) != null) continue
                if (!inFlightPrefetch.add(idx)) continue

                scope.launch(Dispatchers.Default) {
                    try {
                        if (!isActive) return@launch
                        if (memoryCache.get(idx) != null) return@launch
                        val bitmap = renderBitmap(idx) ?: return@launch
                        memoryCache.put(idx, bitmap)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: IllegalStateException) {
                        // Renderer closed while prefetching
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        inFlightPrefetch.remove(idx)
                    }
                }
            }
        }

        private fun renderBitmap(index: Int): Bitmap? {
            val screenWidth = resources.displayMetrics.widthPixels.coerceAtLeast(1)
            return try {
                var bitmap: Bitmap? = null
                synchronized(renderer) {
                    if (index >= count) return null
                    renderer.openPage(index).use { page ->
                        val srcW = page.width.coerceAtLeast(1)
                        val srcH = page.height.coerceAtLeast(1)
                        val renderWidth = screenWidth
                        val renderHeight = (srcH * (screenWidth.toFloat() / srcW)).toInt().coerceAtLeast(1)
                        val bmp = Bitmap.createBitmap(
                            renderWidth,
                            renderHeight,
                            Bitmap.Config.ARGB_8888
                        )
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmap = bmp
                    }
                }
                bitmap
            } catch (e: CancellationException) {
                throw e
            } catch (e: IllegalStateException) {
                null
            }
        }

        private fun renderPageAsync(index: Int, holder: PdfPageViewHolder): Job {
            return scope.launch(Dispatchers.Default) {
                try {
                    if (!isActive || holder.currentPosition != index) return@launch
                    val bitmap = renderBitmap(index) ?: return@launch
                    if (!isActive) return@launch

                    memoryCache.put(index, bitmap)
                    withContext(Dispatchers.Main) {
                        if (isActive && holder.currentPosition == index) {
                            holder.imageView.setImageBitmap(bitmap)
                            holder.imageView.background = null
                        }
                    }
                } catch (e: CancellationException) {
                    // Normal during scroll/recycle/destroy
                } catch (e: IllegalStateException) {
                    // Renderer closed or invalid state during teardown
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }

        override fun getItemCount(): Int = count
    }

    inner class PdfPageViewHolder(val imageView: ZoomableImageView) : RecyclerView.ViewHolder(imageView) {
        var currentPosition: Int = -1
        var renderJob: Job? = null
    }
}
