#import <Foundation/Foundation.h>

@interface Service : NSObject
{
@private
	NSString*		_domain;
	NSString*		_name;
	NSString*		_type;
	uint16_t		_port;
	
	CFRunLoopRef	_runLoop;
	CFSocketRef		_ipv4socket;
	CFSocketRef		_ipv6socket;
	CFNetServiceRef	_netService;
}

- (id) initWithPort:(uint16_t)port;
- (id) initWithDomain:(NSString*)domain name:(NSString*)name type:(NSString*)type port:(uint16_t)port;

- (BOOL) runUsingRunLoop:(NSRunLoop*)runLoop;
- (BOOL) isRunning;
- (void) stop;

- (void) handleNewConnectionWithSocket:(NSSocketNativeHandle)socket fromAddress:(NSData*)address; //To be implemented by subclasses
@end
