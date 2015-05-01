//
// Created by Fabrice Aneche on 06/01/14.
// Copyright (c) 2014 Dailymotion. All rights reserved.
//

#import "NSData+ImageContentType.h"


@implementation NSData (ImageContentType)

+ (NSString *)contentTypeForImageData:(NSData *)data {
    if (data.length) {
        uint8_t c;
        [data getBytes:&c length:1];
        switch (c) {
            case 0xFF:
                return @"image/jpeg";
            
            case 0x47:
                return @"image/gif";
                
            case 0x49:
            case 0x4D:
                return @"image/tiff";
            
            case 0x89: { // PNG or aPNG
                if ([data length] < 16) return nil;
                
                char ident[4] = { '\0' };
                [data getBytes:&ident[0] range:NSMakeRange(1, 3)];
                
                if (strncasecmp(ident, "PNG", 3) != 0) return nil;
                
                int fileLoc = 8;
                do {
                    uint32_t chunkLength = 0;
                    char chunkType[5] = { '\0' };
                    
                    [data getBytes:&chunkLength range:NSMakeRange(fileLoc, 4)];
                    [data getBytes:&chunkType[0] range:NSMakeRange(fileLoc+4, 4)];
                    
                    chunkLength = CFSwapInt32BigToHost(chunkLength);
                    
                    if (strncasecmp(chunkType, "IDAT", 4) == 0 || strncasecmp(chunkType, "IEND", 4) == 0)
                        return @"image/png";
                    if (strncasecmp(chunkType, "acTL", 4) == 0 || strncasecmp(chunkType, "fcTL", 4) == 0)
                        return @"image/apng";
                    
                    fileLoc += 4 + 4 + chunkLength + 4; // len + type + data + crc
                } while (fileLoc + 8 <= data.length);
            } return nil;
            
            case 0x52: { // R as RIFF for WEBP
                if ([data length] < 12) return nil;
                
                NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
                if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"])
                    return @"image/webp";
            } return nil;
            
            default:
                return @"unk";
        }
    }
    
    return nil;
}

@end
