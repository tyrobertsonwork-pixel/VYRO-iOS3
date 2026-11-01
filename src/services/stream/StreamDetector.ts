import { CapacitorHttp } from '@capacitor/core';

export interface StreamInfo {
  url: string;
  container: string;
  mimeType: string;
  fileName?: string;
  headers?: Record<string, string>;
  isSupported: boolean;
  requiresNativePlayer: boolean;
}

export class StreamDetector {
  private static readonly CONTAINER_SIGNATURES: Record<string, number[]> = {
    'mkv': [0x1A, 0x45, 0xDF, 0xA3],
    'mp4': [0x66, 0x74, 0x79, 0x70],
    'avi': [0x52, 0x49, 0x46, 0x46],
    'webm': [0x1A, 0x45, 0xDF, 0xA3],
    'flac': [0x66, 0x4C, 0x61, 0x43],
  };

  private static readonly MIME_TO_CONTAINER: Record<string, string> = {
    'video/x-matroska': 'mkv',
    'video/mkv': 'mkv',
    'video/mp4': 'mp4',
    'video/x-msvideo': 'avi',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'video/x-m4v': 'mp4',
    'audio/flac': 'flac',
    'audio/x-flac': 'flac',
    'application/octet-stream': 'unknown',
  };

  static async detectStream(url: string): Promise<StreamInfo> {
    console.log('[StreamDetector] Analyzing stream:', url);

    try {
      const headResponse = await CapacitorHttp.request({
        url,
        method: 'HEAD',
        headers: {
          'User-Agent': 'VYRO/1.0',
        },
      });

      console.log('[StreamDetector] HEAD response:', {
        status: headResponse.status,
        headers: headResponse.headers,
      });

      const contentType = headResponse.headers['content-type'] || 
                         headResponse.headers['Content-Type'] || '';
      const contentDisposition = headResponse.headers['content-disposition'] || 
                                headResponse.headers['Content-Disposition'] || '';
      
      let fileName: string | undefined;
      const fileNameMatch = contentDisposition.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/);
      if (fileNameMatch && fileNameMatch[1]) {
        fileName = fileNameMatch[1].replace(/['"]/g, '');
      }

      console.log('[StreamDetector] Extracted metadata:', {
        contentType,
        fileName,
      });

      let container = this.MIME_TO_CONTAINER[contentType.split(';')[0].trim()];

      if (!container && fileName) {
        const ext = fileName.split('.').pop()?.toLowerCase();
        if (ext) {
          container = ext;
        }
      }

      if (!container) {
        const urlPath = new URL(url).pathname;
        const ext = urlPath.split('.').pop()?.toLowerCase();
        if (ext && ext.length <= 4) {
          container = ext;
        }
      }

      if (!container || container === 'unknown') {
        console.log('[StreamDetector] Performing content sniffing...');
        container = await this.sniffContainer(url);
      }

      const requiresNativePlayer = this.requiresNativePlayer(container);
      const isSupported = this.isFormatSupported(container);

      const streamInfo: StreamInfo = {
        url,
        container,
        mimeType: contentType || this.containerToMime(container),
        fileName,
        headers: headResponse.headers,
        isSupported,
        requiresNativePlayer,
      };

      console.log('[StreamDetector] Final stream info:', streamInfo);
      return streamInfo;

    } catch (error) {
      console.error('[StreamDetector] Detection failed:', error);
      
      const urlPath = new URL(url).pathname;
      const ext = urlPath.split('.').pop()?.toLowerCase() || 'unknown';
      
      return {
        url,
        container: ext,
        mimeType: this.containerToMime(ext),
        isSupported: this.isFormatSupported(ext),
        requiresNativePlayer: this.requiresNativePlayer(ext),
      };
    }
  }

  private static async sniffContainer(url: string): Promise<string> {
    try {
      const response = await CapacitorHttp.request({
        url,
        method: 'GET',
        headers: {
          'Range': 'bytes=0-16383',
          'User-Agent': 'VYRO/1.0',
        },
        responseType: 'arraybuffer',
      });

      if (response.data) {
        const bytes = new Uint8Array(response.data);
        
        for (const [container, signature] of Object.entries(this.CONTAINER_SIGNATURES)) {
          if (this.matchesSignature(bytes, signature)) {
            console.log(`[StreamDetector] Detected ${container} by signature`);
            return container;
          }
          
          if (container === 'mp4' && bytes.length > 8) {
            if (this.matchesSignature(bytes.slice(4), signature)) {
              console.log('[StreamDetector] Detected mp4 by signature at offset 4');
              return 'mp4';
            }
          }
        }
      }

      return 'unknown';
    } catch (error) {
      console.error('[StreamDetector] Content sniffing failed:', error);
      return 'unknown';
    }
  }

  private static matchesSignature(bytes: Uint8Array, signature: number[]): boolean {
    if (bytes.length < signature.length) return false;
    
    for (let i = 0; i < signature.length; i++) {
      if (bytes[i] !== signature[i]) return false;
    }
    
    return true;
  }

  private static requiresNativePlayer(container: string): boolean {
    const nativeFormats = ['mkv', 'avi', 'flv', 'wmv', 'mov', 'flac'];
    return nativeFormats.includes(container);
  }

  private static isFormatSupported(container: string): boolean {
    const supported = ['mkv', 'mp4', 'm4v', 'mov', 'avi', 'webm', 'flac', 'mp3', 'aac'];
    return supported.includes(container);
  }

  private static containerToMime(container: string): string {
    const mimeMap: Record<string, string> = {
      'mkv': 'video/x-matroska',
      'mp4': 'video/mp4',
      'm4v': 'video/x-m4v',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'webm': 'video/webm',
      'flac': 'audio/flac',
      'mp3': 'audio/mpeg',
      'aac': 'audio/aac',
    };
    
    return mimeMap[container] || 'application/octet-stream';
  }
}
