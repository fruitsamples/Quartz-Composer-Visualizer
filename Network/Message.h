#import <Foundation/Foundation.h>

typedef enum {
	kMessageScreenConfigurationRequest = 0,
	kMessageScreenConfiguration,
	kMessageTime,
	kMessageProcessingComposition,
	kMessageDrawingComposition,
	kMessageCompositionData,
	kMessagePlay,
	kMessageStop,
	kMessageParameters,
} MessageType;

@interface Message : NSObject
{
@public
	MessageType			type;
	id					data;
}

+ (id) messageWithType:(MessageType)type data:(id)data;
@end
