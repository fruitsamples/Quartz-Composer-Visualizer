#import <pthread.h>

#import "Server.h"

//CLASS INTERFACE:

@interface ServerConnection (Private)
- (void) _setServer:(Server*)server;
@end

//CLASS IMPLEMENTATIONS:

@implementation ServerConnection

- (void) _setServer:(Server*)server
{
	_server = server;
}

- (Server*) server
{
	return _server;
}

@end

@implementation Server

- (id) initWithDomain:(NSString*)domain name:(NSString*)name type:(NSString*)type port:(uint16_t)port
{
	if((self = [super initWithDomain:domain name:name type:type port:port])) {
		_connections = [NSMutableArray new];
	}
	
	return self;
}

- (void) finalize
{
	[self stop]; //HACK: Make sure our -stop is executed immediately
	
	[super finalize];
}

- (void) dealloc
{
	[self stop]; //HACK: Make sure our -stop is executed immediately
		
	[_connections release];
	_connections = nil;
	
	[super dealloc];
}

- (NSArray*) connections
{
	NSArray*				connections;
	
	connections = [NSArray arrayWithArray:_connections];
	
	return connections;
}

- (id) delegate
{
	return _delegate;
}

- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (void) handleNewConnectionWithSocket:(NSSocketNativeHandle)socket fromAddress:(NSData*)address
{
	ServerConnection*			connection;
		
	if((connection = [[ServerConnection alloc] initWithSocketHandle:socket])) {
		[_connections addObject:connection];
		[connection _setServer:self];
		[connection setDelegate:_delegate];
		[connection release];
	}
}

- (BOOL) runUsingRunLoop:(NSRunLoop*)runLoop
{
	BOOL				wasRunning = [self isRunning];
	
	if(![super runUsingRunLoop:runLoop])
	return NO;
	
	if(!wasRunning)
	[_delegate serverDidStart:self];
	
	return YES;
}

- (void) stop
{
	NSArray*			connections;
	NSUInteger			i;
	
	if([self isRunning])
	[_delegate serverWillStop:self];
	
	[super stop];
	
	//HACK: To avoid dead-locks in the connection threads, we need to work on a copy
	if(_connections) {
		connections = [self connections];
		for(i = 0; i < [connections count]; ++i)
		[[connections objectAtIndex:i] invalidate];
	}
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08qX | running = %i | %i connections >", [self class], (long)self, [self isRunning], [_connections count]];
}

@end

@implementation NSObject (ServerDelegate)

- (void) serverDidStart:(Server*)server
{
	;
}

- (void) serverWillStop:(Server*)server
{
	;
}

@end
