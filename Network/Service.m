#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

#import "Service.h"
#import "Utils.h"

//FUNCTIONS:

static void _AcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void* data, void* info)
{
	Service*				server = (Service*)info;
	CFSocketNativeHandle	nativeSocketHandle;
	NSInteger				yes = 1;
	
	if(kCFSocketAcceptCallBack == type) { 
		nativeSocketHandle = *(CFSocketNativeHandle*)data;
		setsockopt(nativeSocketHandle, SOL_SOCKET, SO_KEEPALIVE, &yes, sizeof(yes));
		setsockopt(nativeSocketHandle, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
		[server handleNewConnectionWithSocket:nativeSocketHandle fromAddress:(NSData*)address]; //FIXME: Use [CFMakeCollectable(address) autorelease] ?
	}
}

//CLASS IMPLEMENTATION:

@implementation Service

- (id) initWithPort:(uint16_t)port
{
	return [self initWithDomain:nil name:nil type:nil port:port];
}

- (id) initWithDomain:(NSString*)domain name:(NSString*)name type:(NSString*)type port:(uint16_t)port
{
	if((self = [super init])) {
		if([type length]) {
			if(![domain length])
			domain = @""; //NOTE: Equivalent to "local."
			if(![name length])
			name = [(id)CFMakeCollectable(CSCopyMachineName()) autorelease];
			
			_domain = [domain copy];
			_name = [name copy];
			_type = [_ValidateServiceType(type) copy];
		}
		_port = port;
	}
	
	return self;
}

- (void) finalize
{
	[self stop];
	
	[super finalize];
}

- (void) dealloc
{
	[self stop];
	
	[_domain release];
	[_name release];
	[_type release];

	[super dealloc];
}

- (void) handleNewConnectionWithSocket:(NSSocketNativeHandle)socket fromAddress:(NSData*)address
{
	[self doesNotRecognizeSelector:_cmd]; //close(socket);
}

- (BOOL) runUsingRunLoop:(NSRunLoop*)runLoop
{
    CFSocketContext				socketCtxt = {0, self, NULL, NULL, NULL};
	NSInteger					yes = 1;
	struct sockaddr_in			addr4;
	CFDataRef					dataRef;
	CFRunLoopSourceRef			source;
	
	if(_runLoop)
	return YES;
	
	_runLoop = [runLoop getCFRunLoop];
	if(!_runLoop)
	return NO;
	
	_ipv4socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)&_AcceptCallBack, &socketCtxt);
	if(!_ipv4socket) {
		[self stop];
		return NO;
	}
	
	setsockopt(CFSocketGetNative(_ipv4socket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
	
	//Set up the IPv4 endpoint; if port is 0, this will cause the kernel to choose a port for us
	memset(&addr4, 0, sizeof(addr4));
	addr4.sin_len = sizeof(addr4);
	addr4.sin_family = AF_INET;
	addr4.sin_port = htons(_port);
	addr4.sin_addr.s_addr = htonl(INADDR_ANY);
	if(CFSocketSetAddress(_ipv4socket, (CFDataRef)[NSData dataWithBytes:&addr4 length:sizeof(addr4)]) != kCFSocketSuccess) {
		[self stop];
		return NO;
	}
	
	//Now that the binding was successful, we get the port number (we will need it for the v6 endpoint and for the NSNetService)
	if(_port == 0) {
		dataRef = CFSocketCopyAddress(_ipv4socket);
		memcpy(&addr4, CFDataGetBytePtr(dataRef), CFDataGetLength(dataRef));
		_port = ntohs(addr4.sin_port);
		CFRelease(dataRef);
	}

	source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _ipv4socket, 0);
	CFRunLoopAddSource(_runLoop, source, kCFRunLoopCommonModes);
	CFRelease(source);
	
	if(_type) {
		_netService = CFNetServiceCreate(kCFAllocatorDefault, (CFStringRef)_domain, (CFStringRef)_type, (CFStringRef)_name, _port);
		if(_netService == NULL) {
			[self stop];
			return NO;
		}
		CFNetServiceScheduleWithRunLoop(_netService, _runLoop, kCFRunLoopCommonModes);
		if(!CFNetServiceRegisterWithOptions(_netService, 0, NULL)) {
			[self stop];
			return NO;
		}
	}
	
	return YES;
}

- (BOOL) isRunning
{
	return (_runLoop ? YES : NO);
}

- (void) stop
{
	if(_netService) {
		CFNetServiceCancel(_netService);
		CFNetServiceUnscheduleFromRunLoop(_netService, _runLoop, kCFRunLoopCommonModes);
		CFRelease(_netService);
		_netService = NULL;
	}
	if(_ipv4socket) {
		CFSocketInvalidate(_ipv4socket);
		CFRelease(_ipv4socket);
		_ipv4socket = NULL;
	}
	_runLoop = NULL;
}

@end
