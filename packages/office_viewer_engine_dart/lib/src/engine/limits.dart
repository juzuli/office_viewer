/// Hard caps for untrusted office packages (plan §9).
class ResourceLimits {
  const ResourceLimits({
    this.maxCompressedBytes = 100 * 1024 * 1024,
    this.maxUncompressedBytes = 500 * 1024 * 1024,
    this.maxCompressionRatio = 100,
    this.maxEntries = 20000,
    this.maxXmlDepth = 256,
    this.maxElementCount = 5000000,
    this.maxMergedRanges = 100000,
    this.maxSlideShapes = 5000,
    this.maxGroupNesting = 64,
    this.maxTableCells = 100000,
    this.imageCacheBytes = 64 * 1024 * 1024,
    this.displayListCacheBytes = 32 * 1024 * 1024,
  });

  final int maxCompressedBytes;
  final int maxUncompressedBytes;
  final int maxCompressionRatio;
  final int maxEntries;
  final int maxXmlDepth;
  final int maxElementCount;
  final int maxMergedRanges;
  final int maxSlideShapes;
  final int maxGroupNesting;
  final int maxTableCells;
  final int imageCacheBytes;
  final int displayListCacheBytes;

  static const ResourceLimits defaults = ResourceLimits();
}
