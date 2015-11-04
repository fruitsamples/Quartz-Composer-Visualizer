#import "Client.h"
#import "MyApplication.h"
#import "Utils.h"
#import "Message.h"

// IMPLEMENTATIONS:

@implementation Client

- (id) init
{
	if ((self = [super initWithDomain:nil name:nil type:_ValidateServiceType(kClientServiceType) port:kClientPort])) {
		[self setDelegate:self];
		if (![self runUsingRunLoop:[NSRunLoop currentRunLoop]])
		return nil;
	}
	
	return self;
}

- (void) connectionDidOpen:(Connection*)connection
{
	NSLog(@"<CLIENT> Opened connection with host \"%@\"", [connection remoteHostName]);
}

- (void) connectionDidInvalidate:(Connection*)connection
{
	NSLog(@"<CLIENT> Connection with host has been invalidated");
}

- (void) connectionDidReceiveMessage:(Connection*)connection
{
	NSData*				data = [connection receiveDataWithTimeOut:0];
	Message*			message;
	NSDictionary*		param;
	NSArray*			screenArray;
	NSEnumerator*		keyEnumerator;
	NSString*			key;
	NSPoint				screenOrigin;
	
	if (data) {
		message = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		switch (message->type) {
			case kMessageScreenConfigurationRequest:
				//Sending screens coordinates back
				screenArray = [(Screens*)[NSApp valueForKey:@"screens"] screensForKey:[(id)CSCopyMachineName() autorelease]];
				screenArray = [screenArray sortedArrayUsingSelector:@selector(_compare:)];
				screenOrigin = [[screenArray objectAtIndex:0] frame].origin;
				[screenArray makeObjectsPerformSelector:@selector(_translateOriginOfOrigin:) withObject:[NSValue valueWithPointer:&screenOrigin]];  // HACK
				if (![connection sendData:[NSKeyedArchiver archivedDataWithRootObject:screenArray] timeOut:0.0])
				NSLog (@"<CLIENT> Failed sending screen configuration to host \"%@\"", [connection remoteHostName]);
				break;
			case kMessageScreenConfiguration:
				if (message->data) {
					if ([(Screens*)(message->data) screensForKey:[(id)CSCopyMachineName() autorelease]])
					[NSApp setValue:message->data forKey:@"screens"];
					else
					[(MyApplication*)NSApp resetScreens];
				}
				else
				[(MyApplication*)NSApp resetScreens];				
				break;
			case kMessageTime:
				[NSApp setValue:message->data forKey:@"time"];
				break;
			case kMessageDrawingComposition:
				[NSApp setValue: message->data forKey:@"drawingCompositionData"];			
				break;
			case kMessageProcessingComposition:
				[NSApp setValue:message->data forKey:@"processingCompositionData"];
				break;
			case kMessageCompositionData:
				[NSApp setValue:message->data forKey:@"masterCompositionCache"];
				break;
			case kMessageParameters:
				param = message->data;
				keyEnumerator = [param keyEnumerator];
				while ((key = [keyEnumerator nextObject]))
				[NSApp setValue:[param valueForKey:key] forKey:key];
				break;
			case kMessagePlay:
				[(MyApplication*)NSApp play:self];
				break;
			case kMessageStop:
				[(MyApplication*)NSApp stop:self];
				break;
			default:
				NSLog (@"<CLIENT> Unrecognized message type from host \"%@\"", [connection remoteHostName]);
				return;
		}
	
	}
}

@end
