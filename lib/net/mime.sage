# MIME type lookup and utilities
# Maps file extensions to content types for HTTP servers

# Core MIME type database
proc lookup(ext):
    # Text types
    if ext == "html" or ext == "htm":
        return "text/html"
    if ext == "css":
        return "text/css"
    if ext == "js" or ext == "mjs":
        return "application/javascript"
    if ext == "json":
        return "application/json"
    if ext == "xml":
        return "application/xml"
    if ext == "txt" or ext == "text":
        return "text/plain"
    if ext == "csv":
        return "text/csv"
    if ext == "md" or ext == "markdown":
        return "text/markdown"
    if ext == "yaml" or ext == "yml":
        return "text/yaml"
    if ext == "toml":
        return "application/toml"
    # Image types
    if ext == "png":
        return "image/png"
    if ext == "jpg" or ext == "jpeg":
        return "image/jpeg"
    if ext == "gif":
        return "image/gif"
    if ext == "svg":
        return "image/svg+xml"
    if ext == "ico":
        return "image/x-icon"
    if ext == "webp":
        return "image/webp"
    if ext == "bmp":
        return "image/bmp"
    if ext == "tiff" or ext == "tif":
        return "image/tiff"
    if ext == "avif":
        return "image/avif"
    # Audio types
    if ext == "mp3":
        return "audio/mpeg"
    if ext == "wav":
        return "audio/wav"
    if ext == "ogg":
        return "audio/ogg"
    if ext == "flac":
        return "audio/flac"
    if ext == "aac":
        return "audio/aac"
    if ext == "weba":
        return "audio/webm"
    # Video types
    if ext == "mp4":
        return "video/mp4"
    if ext == "webm":
        return "video/webm"
    if ext == "avi":
        return "video/x-msvideo"
    if ext == "mkv":
        return "video/x-matroska"
    if ext == "mov":
        return "video/quicktime"
    # Font types
    if ext == "woff":
        return "font/woff"
    if ext == "woff2":
        return "font/woff2"
    if ext == "ttf":
        return "font/ttf"
    if ext == "otf":
        return "font/otf"
    # Archive types
    if ext == "zip":
        return "application/zip"
    if ext == "gz" or ext == "gzip":
        return "application/gzip"
    if ext == "tar":
        return "application/x-tar"
    if ext == "bz2":
        return "application/x-bzip2"
    if ext == "xz":
        return "application/x-xz"
    if ext == "7z":
        return "application/x-7z-compressed"
    if ext == "rar":
        return "application/vnd.rar"
    # Document types
    if ext == "pdf":
        return "application/pdf"
    if ext == "doc":
        return "application/msword"
    if ext == "docx":
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    if ext == "xls":
        return "application/vnd.ms-excel"
    if ext == "xlsx":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    # Programming
    if ext == "wasm":
        return "application/wasm"
    if ext == "map":
        return "application/json"
    # Binary / fallback
    if ext == "bin" or ext == "exe" or ext == "dll" or ext == "so":
        return "application/octet-stream"
    return "application/octet-stream"

# Get MIME type from a filename
proc from_filename(filename):
    let last_dot = -1
    for i in range(len(filename)):
        if filename[i] == ".":
            last_dot = i
    if last_dot < 0:
        return "application/octet-stream"
    let ext = ""
    for i in range(len(filename) - last_dot - 1):
        let c = filename[last_dot + 1 + i]
        let code = ord(c)
        if code >= 65 and code <= 90:
            ext = ext + chr(code + 32)
        else:
            ext = ext + c
    return lookup(ext)

# Check if a MIME type is text-based
proc is_text(content_type):
    if len(content_type) >= 5:
        let prefix = content_type[0] + content_type[1] + content_type[2] + content_type[3] + content_type[4]
        if prefix == "text/":
            return true
    if content_type == "application/json":
        return true
    if content_type == "application/xml":
        return true
    if content_type == "application/javascript":
        return true
    if content_type == "image/svg+xml":
        return true
    return false

# Check if a MIME type is an image
proc is_image(content_type):
    if len(content_type) >= 6:
        let prefix = content_type[0] + content_type[1] + content_type[2] + content_type[3] + content_type[4] + content_type[5]
        if prefix == "image/":
            return true
    return false

# Get the general category of a MIME type
proc category(content_type):
    for i in range(len(content_type)):
        if content_type[i] == "/":
            let cat = ""
            for j in range(i):
                cat = cat + content_type[j]
            return cat
    return "application"
