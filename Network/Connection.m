#import <unistd.h>
#import <netinet/in.h>

#import "Connection.h"
#import "Utils.h"

//CONSTANTS:

#define kMagic						0x1234ABCD
#define kResolveRunLoopMode			CFSTR("ResolveRunLoopMode")

//STRUCTURE:

typedef struct {
	NSUInteger		magic;
	NSUInteger		length;
} Header; //WARNING: Big-ending

//CLASS INTERFACE:

@interface Connection (Internal)
- (void) _handleStreamEvent:(CFStreamEventType)type forStream:(CFTypeRef)stream;
@end


static NSString* _IPAddressToString(const void* data)
{
	struct sockaddr*				address = (struct sockaddr*)data;
	struct sockaddr_in*				address4 = (struct sockaddr_in*)data;
	struct sockaddr_in6*			address6 = (struct sockaddr_in6*)data;
	in_addr_t						temp;
	
	switch(address->sa_family) {
		
		case AF_INET:
		temp = ntohl(address4->sin_addr.s_addr);
		return [NSString stringWithFormat:@"%i.%i.%i.%i", (temp >> 24) & 0xFF, (temp >> 16) & 0xFF, (temp >> 8) & 0xFF, (temp >> 0) & 0xFF];
		
		case AF_INET6:
		return [NSString stringWithFormat:@"%04X:%04X:%04X:%04X:%04X:%04X:%04X:%04X", ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[0]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[1]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[2]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[3]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[4]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[5]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[6]), ntohs(address6->sin6_addr.__u6_addr.__u6_addr16[7])];
		
	}
	
	return nil;
}

static NSString* _IPAddressesToString(CFArrayRef addresses)
{
	NSString*						string = nil;
	NSUInteger						i;
	struct sockaddr*				address;
	
	if(addresses)
	for(i = 0; i < CFArrayGetCount(addresses); ++i) {
		address = (struct sockaddr*)CFDataGetBytePtr((CFDataRef)CFArrayGetValueAtIndex(addresses, i));
		string = _IPAddressToString(address);
		if(string && (address->sa_family == AF_INET)) //HACK: Prefer IPv4 addresses
		break;
	}
	
	return string;
}

static void _ReadClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	[(Connection*)clientCallBackInfo _handleStreamEvent:type forStream:stream];
}

static void _WriteClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	[(Connection*)clientCallBackInfo _handleStreamEvent:type forStream:stream];
}

//CLASS IMPLEMENTATION:

@implementation Connection

- (id) _initWithRunLoop:(CFRunLoopRef)runLoop readStream:(CFReadStreamRef)input writeStream:(CFWriteStreamRef)output
{
	CFStreamClientContext	context = {0, self, NULL, NULL, NULL};
	
	if((self = [super init])) {
		_inputStream = (CFReadStreamRef)CFRetain(input);
		_outputStream = (CFWriteStreamRef)CFRetain(output);
		_runLoop = runLoop;
		
		CFReadStreamSetClient(_inputStream, kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _ReadClientCallBack, &context);
		CFReadStreamScheduleWithRunLoop(_inputStream, _runLoop, kCFRunLoopCommonModes);
		CFWriteStreamSetClient(_outputStream, kCFStreamEventOpenCompleted | kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _WriteClientCallBack, &context);
		CFWriteStreamScheduleWithRunLoop(_outputStream, _runLoop, kCFRunLoopCommonModes);
		
		if(!CFReadStreamOpen(_inputStream) || !CFWriteStreamOpen(_outputStream)) {
			[self release];
			return nil;
		}
		
		_inputMessages = [NSMutableArray new];
		_outputMessages = [NSMutableArray new];
		
		_active = YES;
	}
	
	return self;
}

- (id) initWithSocketHandle:(NSSocketNativeHandle)socket
{
	CFReadStreamRef			readStream = NULL;
	CFWriteStreamRef		writeStream = NULL;
	
	CFStreamCreatePairWithSocket(kCFAllocatorDefault, socket, &readStream, &writeStream);
	if(!readStream || !writeStream) {
		close(socket);
		if(readStream)
		CFRelease(readStream);
		if(writeStream)
		CFRelease(writeStream);
		[self release];
		return nil;
	}
	
	CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
	CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
	self = [self _initWithRunLoop:CFRunLoopGetCurrent() readStream:readStream writeStream:writeStream];
	CFRelease(readStream);
	CFRelease(writeStream);
	
	return self;
}

- (id) initWithCFNetService:(CFNetServiceRef)service timeOut:(NSTimeInterval)timeOut
{
	CFReadStreamRef			readStream = NULL;
	CFWriteStreamRef		writeStream = NULL;
	
	if(!service || ((timeOut > 0.0) && !CFNetServiceGetAddressing(service) && !CFNetServiceResolveWithTimeout(service, timeOut, NULL))) {
		[self release];
		return nil;
	}
	
	CFStreamCreatePairWithSocketToNetService(kCFAllocatorDefault, service, &readStream, &writeStream);
	if(!readStream || !writeStream) {
		if(readStream)
		CFRelease(readStream);
		if(writeStream)
		CFRelease(writeStream);
		[self release];
		return nil;
	}
	
	self = [self _initWithRunLoop:CFRunLoopGetCurrent() readStream:readStream writeStream:writeStream];
	CFRelease(readStream);
	CFRelease(writeStream);
	
	return self;
}

- (id) initWithServiceDomain:(NSString*)domain type:(NSString*)type name:(NSString*)name timeOut:(NSTimeInterval)timeOut
{
	CFNetServiceRef			service;
	
	service = CFNetServiceCreate(kCFAllocatorDefault, (CFStringRef)domain, (CFStringRef)_ValidateServiceType(type), (CFStringRef)name, 0);
	if(service == NULL) {
		[self release];
		return nil;
	}
	
	self = [self initWithCFNetService:service timeOut:timeOut];
	CFRelease(service);
	
	return self;
}

- (id) initWithNetService:(NSNetService*)service
{
	CFNetServiceRef			serviceRef;
	
	//HACK: We cannot resolve a NSNetService as it is in asynchronous mode on an unknown runloop
	serviceRef = CFNetServiceCreate(kCFAllocatorDefault, (CFStringRef)[service domain], (CFStringRef)[service type], (CFStringRef)[service name], 0);
	if(!serviceRef) {
		[self release];
		return nil;
	}
	
	self = [self initWithCFNetService:serviceRef timeOut:0.0];
	CFRelease(serviceRef);
	
	return self;
}

- (void) finalize
{
	[self invalidate];
	
	[super finalize];
}

- (void) dealloc
{
	[self invalidate];
	
	[_address release];
	[_name release];
	
	[super dealloc];
}

- (id) delegate
{
	return _delegate;
}

- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (BOOL) isOpened
{
	return (_runLoop && _opened ? YES : NO);
}

- (NSString*) remoteHostName
{
	return _name;
}

- (NSString*) remoteAddress
{
	return _address;
}

- (BOOL) isValid
{
	return (_runLoop ? YES : NO);
}

- (BOOL) active
{
	return _active;
}

- (void) setActive:(BOOL)act
{
	_active = act;
}

- (void) invalidate
{
	if(_runLoop) {
		if(_inputPending) {
			CFRunLoopStop(_runLoop);
			_inputPending = NO;
		}
		if(_outputPending) {
			CFRunLoopStop(_runLoop);
			_outputPending = NO;
		}
		_runLoop = NULL;
		
		if(_inputStream) {
			CFReadStreamClose(_inputStream);
			CFReadStreamSetClient(_inputStream, kCFStreamEventNone, NULL, NULL);
			CFRelease(_inputStream);
			_inputStream = NULL;
		}
		if(_inputData) {
			[_inputData release];
			_inputData = nil;
		}
		if(_inputMessages) {
			[_inputMessages release];
			_inputMessages = nil;
		}
		
		if(_outputStream) {
			CFWriteStreamClose(_outputStream);
			CFWriteStreamSetClient(_outputStream, kCFStreamEventNone, NULL, NULL);
			CFRelease(_outputStream);
			_outputStream = NULL;
		}
		if(_outputData) {
			[_outputData release];
			_outputData = nil;
		}
		if(_outputMessages) {
			[_outputMessages release];
			_outputMessages = nil;
		}
		
		[_delegate connectionDidInvalidate:self];
	}
}

- (CFRunLoopRef) _runLoop
{
	return _runLoop;
}

- (BOOL) _writeData
{
	CFIndex					result;
	Header					header;
	
	if(_outputData == nil) {
		_outputData = [[_outputMessages objectAtIndex:0] retain];
		_outputCapacity = 0;
		[_outputMessages removeObjectAtIndex:0];
	}
	
	if(_outputCapacity == 0) {
		header.magic = NSSwapHostIntToBig(kMagic);
		header.length = NSSwapHostIntToBig([_outputData length]);
		result = CFWriteStreamWrite(_outputStream, (const UInt8*)&header, sizeof(Header));
		if(result != sizeof(Header))
		return NO;
	}
	
	result = CFWriteStreamWrite(_outputStream, (UInt8*)[_outputData bytes] + _outputCapacity, [_outputData length] - _outputCapacity);
	if(result <= 0)
	return NO;
	
	_outputCapacity += result;
	if(_outputCapacity == [_outputData length]) {
		[_outputData release];
		_outputData = nil;
		if(_outputPending && ![_outputMessages count]) {
			CFRunLoopStop(_runLoop);
			_outputPending = NO;
		}
	}
	
	return YES;
}

- (BOOL) _readData
{
	CFIndex					result;
	Header					header;
	
	if(_inputData == nil) {
		result = CFReadStreamRead(_inputStream, (UInt8*)&header, sizeof(Header));
		if(result < sizeof(Header))
		return NO;
		if(NSSwapBigIntToHost(header.magic) != kMagic)
		return NO;
		result = NSSwapBigIntToHost(header.length);
		_inputData = [[NSMutableData alloc] initWithCapacity:result];
		[_inputData setLength:result];
		_inputCapacity = 0;
	}
	
	result = CFReadStreamRead(_inputStream, (UInt8*)[_inputData mutableBytes] + _inputCapacity, [_inputData length] - _inputCapacity);
	if(result <= 0)
	return NO;
	_inputCapacity += result;
	
	if(_inputCapacity == [_inputData length]) {
		[_inputMessages addObject:_inputData];
		
		if(_inputPending) {
			CFRunLoopStop(_runLoop);
			_inputPending = NO;
		}
		else
		[_delegate connectionDidReceiveMessage:self];
		[_inputData release];
		_inputData = nil;
	}	
	
	return YES;
}

- (void) _updateRemoteInfo:(CFTypeRef)stream
{
	char					buffer[SOCK_MAXADDRLEN];
	socklen_t				length = SOCK_MAXADDRLEN;
	NSInteger				yes = 1;
	CFHostRef				host;
	CFNetServiceRef			service;
	CFDataRef				data;
	CFSocketNativeHandle	socket;
	CFStringRef				name;
	CFDataRef				addressData;
	
	if(_address) {
		[_address release];
		_address = nil;
	}
	if(_name) {
		[_name release];
		_name = nil;
	}
	
	if((data = (CFGetTypeID(stream) == CFWriteStreamGetTypeID() ? CFWriteStreamCopyProperty((CFWriteStreamRef)stream, kCFStreamPropertySocketNativeHandle) : CFReadStreamCopyProperty((CFReadStreamRef)stream, kCFStreamPropertySocketNativeHandle)))) {
		CFDataGetBytes(data, CFRangeMake(0, sizeof(CFSocketNativeHandle)), (UInt8*)&socket);
		setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, &yes, sizeof(yes));
		CFRelease(data);
	}
	
	if((host = (CFHostRef)(CFGetTypeID(stream) == CFWriteStreamGetTypeID() ? CFWriteStreamCopyProperty((CFWriteStreamRef)stream, kCFStreamPropertySocketRemoteHost) : CFReadStreamCopyProperty((CFReadStreamRef)stream, kCFStreamPropertySocketRemoteHost)))) {
		_address = [_IPAddressesToString(CFHostGetAddressing(host, NULL)) retain];
		_name = (CFHostGetNames(host, NULL) ? [[NSString alloc] initWithString:(NSString*)CFArrayGetValueAtIndex(CFHostGetNames(host, NULL), 0)] : nil);
		CFRelease(host);
	}
	else if((service = (CFNetServiceRef)(CFGetTypeID(stream) == CFWriteStreamGetTypeID() ? CFWriteStreamCopyProperty((CFWriteStreamRef)stream, kCFStreamPropertySocketRemoteNetService) : CFReadStreamCopyProperty((CFReadStreamRef)stream, kCFStreamPropertySocketRemoteNetService)))) {
		_address = [_IPAddressesToString(CFNetServiceGetAddressing(service)) retain];
		_name = (CFNetServiceGetName(service) ? [[NSString alloc] initWithString:(NSString*)CFNetServiceGetName(service)] : nil);
		CFRelease(service);
	}
	else if((data = (CFGetTypeID(stream) == CFWriteStreamGetTypeID() ? CFWriteStreamCopyProperty((CFWriteStreamRef)stream, kCFStreamPropertySocketNativeHandle) : CFReadStreamCopyProperty((CFReadStreamRef)stream, kCFStreamPropertySocketNativeHandle)))) {
		if((name = (CFGetTypeID(stream) == CFWriteStreamGetTypeID() ? CFWriteStreamCopyProperty((CFWriteStreamRef)stream, kCFStreamPropertySocketRemoteHostName) : CFReadStreamCopyProperty((CFReadStreamRef)stream, kCFStreamPropertySocketRemoteHostName)))) {
			_name = [[NSString alloc] initWithString:(NSString*)name];
			CFRelease(name);
		}
		
		CFDataGetBytes(data, CFRangeMake(0, sizeof(CFSocketNativeHandle)), (UInt8*)&socket);
		if(getpeername(socket, (struct sockaddr*)buffer, &length) == 0) {
			_address = [_IPAddressToString(buffer) retain];
			if(_name == nil) { //FIXME: Is there a better way to retrieve the host name from the socket?
				if((addressData = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (UInt8*)buffer, length, kCFAllocatorNull))) {
					if((host = CFHostCreateWithAddress(kCFAllocatorDefault, addressData))) {
						if(CFHostStartInfoResolution(host, kCFHostNames, NULL))
						_name = (CFHostGetNames(host, NULL) ? [[NSString alloc] initWithString:(NSString*)CFArrayGetValueAtIndex(CFHostGetNames(host, NULL), 0)] : nil);
						CFRelease(host);
					}
					CFRelease(addressData);
				}
			}
		}
		CFRelease(data);
	}
}

- (void) _handleStreamEvent:(CFStreamEventType)type forStream:(CFTypeRef)stream
{
	switch(type) {
		
		case kCFStreamEventHasBytesAvailable:
		if(!_opened) {
			_opened = YES;
			[self _updateRemoteInfo:stream];
			[_delegate connectionDidOpen:self];
		}
		do {
			if(![self _readData])
			[self invalidate];
		} while(_inputStream && CFReadStreamHasBytesAvailable(_inputStream));
		break;
		
		case kCFStreamEventCanAcceptBytes:
		if(!_opened) {
			_opened = YES;
			[self _updateRemoteInfo:stream];
			[_delegate connectionDidOpen:self];
		}
		while((_outputData || [_outputMessages count]) && _outputStream && CFWriteStreamCanAcceptBytes(_outputStream)) {
			if(![self _writeData])
			[self invalidate];
		}
		break;
		
		case kCFStreamEventEndEncountered:
		[self invalidate];
		break;
		
		case kCFStreamEventErrorOccurred:
		[self invalidate];
		break;
		
		default: //kCFStreamEventOpenCompleted - kCFStreamEventNone
		break;
		
	}
}

- (BOOL) sendData:(NSData*)data timeOut:(NSTimeInterval)limit
{
	if((_runLoop != CFRunLoopGetCurrent()) || (data == nil) || _outputPending)
	return NO;
	
	[_outputMessages addObject:data];
	if(CFWriteStreamCanAcceptBytes(_outputStream))
	[self _writeData];
	if(limit <= 0.0)
	return YES;
	
	if(_outputData || [_outputMessages count]) {
		_outputPending = YES;
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, limit, false);
	}
	
	return (_runLoop ? YES : NO);	
}

- (NSData*) receiveDataWithTimeOut:(NSTimeInterval)limit
{
	NSData*			data;
	
	if((_runLoop != CFRunLoopGetCurrent()) || _inputPending)
	return nil;
	
	if([_inputMessages count]) {
		data = [[_inputMessages objectAtIndex:0] retain];
		[_inputMessages removeObjectAtIndex:0];
		return [data autorelease];
	}
	else if(limit <= 0.0)
	return nil;
	
	_inputPending = YES;
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, limit, false);
	
	if([_inputMessages count]) {
		data = [[_inputMessages objectAtIndex:0] retain];
		[_inputMessages removeObjectAtIndex:0];
		return [data autorelease];
	}
	
	return nil;
}

- (NSData*) sendDataAndWaitForResponse:(NSData*)data timeOut:(NSTimeInterval)limit
{
	CFAbsoluteTime		time;
	BOOL				success;
	
	if((limit <= 0.0) || _inputPending || _outputPending)
	return nil;
	
	time = CFAbsoluteTimeGetCurrent();
	success = [self sendData:data timeOut:limit];
	time = CFAbsoluteTimeGetCurrent() - time;
	if(!success)
	return nil;
	limit -= time;
	
	data = nil;
	while((limit >= 0.0) && !data) {
		time = CFAbsoluteTimeGetCurrent();
		_inputPending = YES;
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, limit, false);
		time = CFAbsoluteTimeGetCurrent() - time;
		if(_runLoop == NULL)
		break;
		
		if ([_inputMessages count]) {
			data = [[_inputMessages objectAtIndex:0] retain];
			[_inputMessages removeObjectAtIndex:0];
		}
		
		if([self isValid])
		limit -= time;
		else
		limit = 0.0;
	}
	
	if([_inputMessages count])
	[_delegate connectionDidReceiveMessage:self];
	
	return data;
}

- (BOOL) hasDataAvailable
{
	return ([_inputMessages count] ? YES : NO);
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08qX | valid = %i | opened = %i | address = %@ (%@) | in messages = %i | out messages = %i >", [self class], (long)self, _runLoop != 0, _opened, _address, _name, [_inputMessages count], [_outputMessages count]];
}

@end

@implementation NSObject (ConnectionDelegate)

- (void) connectionDidOpen:(Connection*)connection
{
	;
}

- (void) connectionDidInvalidate:(Connection*)connection
{
	;
}

- (void) connectionDidReceiveMessage:(Connection*)connection
{
	;
}

@end
