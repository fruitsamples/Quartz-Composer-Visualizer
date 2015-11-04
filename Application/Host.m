#import <sys/socket.h>
#import <netinet/in.h>

#import "Host.h"
#import "Utils.h"
#import "Message.h"
#import "MyApplication.h"

// CONSTANTS:

#define kServiceResolveTimeOut				30.0 //seconds

// FUNCTIONS:

static void _NetServiceBrowserCallBack(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService, CFStreamError* error, void* info)
{
	if(flags & kCFNetServiceFlagIsDomain)
	return;
		
	if (domainOrService) {
		if(flags & kCFNetServiceFlagRemove)
		[(Host*)info removeClient:(CFNetServiceRef)domainOrService];
		else
		[(Host*)info addClient:(CFNetServiceRef)domainOrService];
	}
}

@implementation Host

- (id) init
{
	CFNetServiceClientContext		serviceContext = {0, self, NULL, NULL, NULL};
	
	if ((self = [super init])) {
		_clients = [NSMutableArray new];
		_browser = CFNetServiceBrowserCreate(kCFAllocatorDefault, _NetServiceBrowserCallBack, &serviceContext);
		if(_browser) {
			CFNetServiceBrowserScheduleWithRunLoop(_browser, CFRunLoopGetCurrent(), (CFStringRef)kCFRunLoopCommonModes);
			if (!CFNetServiceBrowserSearchForServices(_browser, CFSTR("local."), (CFStringRef)_ValidateServiceType(kServerServiceType), NULL)) {
				[self release];
				return nil;
			}
		}
	}
	
	return self;
}

- (void) dealloc
{
	CFStreamError	error;
	
	// Release clients connection references
	[_clients release];	
	if(_browser) {
		CFNetServiceBrowserUnscheduleFromRunLoop(_browser,  CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFNetServiceBrowserInvalidate(_browser);
		CFNetServiceBrowserStopSearch(_browser, &error);		
		CFRelease(_browser);
	}

	[super dealloc];
}

- (void) addClient:(CFNetServiceRef)clientServiceRef
{
	Connection*					connection;
	NSString*					name = (NSString*)CFNetServiceGetName((CFNetServiceRef)clientServiceRef);
	NSArray*					screens;
	NSData*						data;
	BOOL						unique = YES;
	NSUInteger					i;

	if (![name isEqualToString:[(id)CSCopyMachineName() autorelease]]) {
		NSLog(@"<HOST> Autoconnection to client \"%@\"...", name);
	
		connection = [[Connection alloc] initWithCFNetService:(CFNetServiceRef)clientServiceRef timeOut:kServiceResolveTimeOut];
		if (connection) {
			[connection setDelegate:self];
			data = [NSKeyedArchiver archivedDataWithRootObject:[Message messageWithType:kMessageScreenConfigurationRequest data:nil]];

			if ((data = [connection sendDataAndWaitForResponse:data timeOut:kServiceResolveTimeOut])) {
				screens = [NSKeyedUnarchiver unarchiveObjectWithData:data];

				for (i=0; i<[_clients count]; ++i) {
					if ([name isEqualToString:[[_clients objectAtIndex:i] objectAtIndex:0]]) {
						unique = NO;
						[[NSAlert alertWithMessageText:@"Conflict" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"A machine with the same name is already on the network. Please use unique machine names."] runModal];
					}
				}
				if (unique) {
					[_clients addObject:[NSArray arrayWithObjects:name, connection, screens, nil]];
					[(MyApplication*)NSApp addClient:name screens:screens];
					NSLog(@"<HOST> Connection to client \"%@\" established successfully!", name);
				}
			} 
			else
			NSLog(@"<HOST> Failed retrieving configuration information from client \"%@\"", name);
			
			[connection release];
		}
		else
		NSLog(@"<HOST> Failed connecting to client \"%@\"", name);	
	}
}

- (void) removeClient:(CFNetServiceRef)clientServiceRef
{	
	NSInteger			i;
	NSString*			name = (NSString*)CFNetServiceGetName((CFNetServiceRef)clientServiceRef);

	if (![name isEqualToString:[(id)CSCopyMachineName() autorelease]]) {
		for (i=[_clients count]-1; i>=0; --i) {
			if ([(NSString*)[[_clients objectAtIndex:i] objectAtIndex:0] isEqualToString:name]) {
				[(Connection*)[[_clients objectAtIndex:i] objectAtIndex:1] invalidate]; 
				[_clients removeObjectAtIndex:i];
			}
		}
		
		[(MyApplication*)NSApp removeClient:name];
	}
}

- (NSArray*)clients
{
	return _clients;
}

- (BOOL) hasClients
{
	NSInteger			i;
	BOOL				result = NO;
	Connection*			connection;

	for (i=[_clients count]-1; i>=0; --i) {
		connection = [(NSArray*)[_clients objectAtIndex:i] objectAtIndex:1];
		if ([connection isValid] && [connection active]) {
			result = YES;
			break;
		}
	}
	
	return result;
}

- (void) setActive:(BOOL)active forClientAtIndex:(NSUInteger)index
{
	Connection*			connection;
	BOOL				previous;
	NSArray*			screens;
	NSPoint				screenOrigin;
	
	connection = [[_clients objectAtIndex:index] objectAtIndex:1];
	previous = [connection active];
	if (previous != active) {
		if (active) {
			[connection setActive:active];
			screens = [[_clients objectAtIndex:index] objectAtIndex:2];
			screens = [screens sortedArrayUsingSelector:@selector(_compare:)];
			screenOrigin = [[screens objectAtIndex:0] frame].origin;
			[screens makeObjectsPerformSelector:@selector(_translateOriginOfOrigin:) withObject:[NSValue valueWithPointer:&screenOrigin]];  // HACK
			[(MyApplication*)NSApp addClient:[[_clients objectAtIndex:index] objectAtIndex:0] screens:screens];
		}
		else {
			[(MyApplication*)NSApp removeClient:[[_clients objectAtIndex:index] objectAtIndex:0]];		
			[connection setActive:active];
		}		
	}
}

- (void) _sendMessageToAllClients:(Message*)message
{
	NSUInteger			i;
    NSData*				data = [NSKeyedArchiver archivedDataWithRootObject:message];
	Connection*			connection;
	
	for (i=0; i<[_clients count]; ++i) {
		connection = [[_clients objectAtIndex:i] objectAtIndex:1];
		if ([connection isValid] && [connection active] && ![connection sendData:data timeOut:0.0])
		NSLog(@"<HOST> Failed sending data to client \"%@\"", [connection remoteHostName]);
	}
}

- (void) broadcastScreenConfiguration:(Screens*)screens
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageScreenConfiguration data:screens]];
}

- (void) broadcastDrawingComposition:(NSData*)comp
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageDrawingComposition data:comp]];
}

- (void) broadcastProcessingComposition:(NSData*)comp
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageProcessingComposition data:comp]];
}

- (void) broadcastMasterCompositionData:(NSDictionary*)param
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageCompositionData data:param]];	
}

- (void) broadcastTime:(NSTimeInterval)time
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageTime data:[NSNumber numberWithDouble:time]]];
}

- (void) broadcastApplicationParameters:(NSDictionary*)param
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageParameters data:param]];
}

- (void) broadcastPlay
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessagePlay data:nil]];
}

- (void) broadcastStop
{
	[self _sendMessageToAllClients:[Message messageWithType:kMessageStop data:nil]];
}

@end
