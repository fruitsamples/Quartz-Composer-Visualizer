#import "Screens.h"

@interface Host : NSObject
{
@private
	CFNetServiceBrowserRef		_browser;
	NSString*					_clientsType;
	NSMutableArray*				_clients;	
}

/* Managing clients */
- (void) addClient:(CFNetServiceRef)client;
- (void) removeClient:(CFNetServiceRef)client;
- (NSArray*) clients;
- (BOOL) hasClients;
- (void) setActive:(BOOL)active forClientAtIndex:(NSUInteger)index;

/* Convenience methods for sending data to all registered and active clients */
- (void) broadcastScreenConfiguration:(Screens*)screens;
- (void) broadcastProcessingComposition:(NSData*)comp;
- (void) broadcastDrawingComposition:(NSData*)comp;
- (void) broadcastMasterCompositionData:(NSDictionary*)param;
- (void) broadcastTime:(NSTimeInterval)time;
- (void) broadcastApplicationParameters:(NSDictionary*)param;
- (void) broadcastPlay;
- (void) broadcastStop;

@end
