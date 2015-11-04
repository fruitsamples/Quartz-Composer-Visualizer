#import "ProcessingRenderer.h"

//FUNCTIONS:

static NSString* _ConvertType(NSString* type)
{
	if ([type isEqualToString:QCPortTypeBoolean] || [type isEqualToString:QCPortTypeIndex] || [type isEqualToString:QCPortTypeNumber])
		return @"NSNumber";
	else if ([type isEqualToString:QCPortTypeImage])
		return @"QCImage";
	else if ([type isEqualToString:QCPortTypeString])
		return @"NSString";
	else if ([type isEqualToString:QCPortTypeColor])
		return @"CIColor";
	else if ([type isEqualToString:QCPortTypeStructure])
		return @"QCStructure";
	else {
		NSLog (@"Error _ConvertType");
		return nil;
	}
}

//CLASS IMPLEMENTATION:

@implementation ProcessingRenderer

- (id) initWithComposition:(QCComposition*)composition framerate:(double)fps
{
	pthread_mutex_t			initMutex;
	pthread_cond_t			initCond;
	BOOL					success;
	
	pthread_mutex_init(&initMutex, NULL);
	pthread_cond_init(&initCond, NULL);
	
	_isRunning = YES;
	pthread_mutex_lock(&initMutex);
	// Processing renderer needs to be initiliazed in rendering thread for Quicktime movies to play.
	[NSThread detachNewThreadSelector:@selector(_startThread:) toTarget:self withObject:[NSDictionary dictionaryWithObjectsAndKeys:composition, @"composition", [NSNumber numberWithDouble:fps], @"framerate", [NSValue valueWithPointer:&success], @"success", [NSValue valueWithPointer:&initMutex], @"mutex", [NSValue valueWithPointer:&initCond], @"condition", nil]];
	pthread_cond_wait(&initCond, &initMutex);
	pthread_mutex_unlock(&initMutex);

	pthread_mutex_destroy(&initMutex);
	pthread_cond_destroy(&initCond);

	if (success)
	return self;
	else
	return nil;
}

- (void) dealloc
{
	[super dealloc];
}

- (void) _processComposition:(id)userInfo
{
	NSTimeInterval		time;
	NSUInteger			i, argCount;
	NSDictionary*		arguments = nil, *outputKeyTypes;
	NSArray*			outputKeys;
	NSString*			key;
	NSAutoreleasePool*	pool = [[NSAutoreleasePool alloc] init];
	
	if (_startTime < 0)
	_startTime = [NSDate timeIntervalSinceReferenceDate];
	time = [NSDate timeIntervalSinceReferenceDate] - _startTime;
	
	// Remove last event from the queue if any
	pthread_mutex_lock(&_eventMutex);
	argCount = [_eventQueue count];
	if (argCount) {
		arguments = [[_eventQueue objectAtIndex:argCount-1] retain];
		[_eventQueue removeObjectAtIndex:argCount-1];
	}
	pthread_mutex_unlock(&_eventMutex);
	
	// Render the composition at current time
	[_renderer renderAtTime:time arguments:arguments];
	
	// Get the output value and cache them in a dictonary
	outputKeys = [_renderer outputKeys];
	outputKeyTypes = [_renderer attributes];
	pthread_mutex_lock(&_resultParametersMutex);
	for (i=0; i<[outputKeys count]; ++i) {
		key = [outputKeys objectAtIndex:i];
		[_resultParameters setValue:[_renderer valueForOutputKey:key ofType:_ConvertType([[outputKeyTypes valueForKey:key] valueForKey:QCPortAttributeTypeKey])] forKey:key];
	}
	pthread_mutex_unlock(&_resultParametersMutex);
	[pool release];
}

- (void) _startThread:(id)userInfo
{
	NSAutoreleasePool*	pool = [[NSAutoreleasePool alloc] init];
	CGColorSpaceRef		colorspace = CGDisplayCopyColorSpace(kCGDirectMainDisplay);
	double				fps = [[(NSDictionary*)userInfo valueForKey:@"framerate"] doubleValue];
	BOOL*				success = [[(NSDictionary*)userInfo valueForKey:@"success"] pointerValue];

	*success = YES;
	pthread_mutex_lock((pthread_mutex_t*)[[(NSDictionary*)userInfo valueForKey:@"mutex"] pointerValue]);
	if(!colorspace) {
		NSLog(@"Failed creating CGColorSpace");
		*success = YES;
	}
	else {
		@try {	// QCRenderer need to be initialized in the same thread it will be renderer with for Quicktime
			_renderer = [[QCRenderer alloc] initWithComposition:(QCComposition *)[userInfo valueForKey:@"composition"] colorSpace:colorspace]; // Note: For the screen that have a different colorspace, an extra conversion step will be made by QC, reducing perf.	CGColorSpaceRelease(colorspace);
		}
		@catch (NSException* exception) {
			[self release];
			*success = NO;
		}	
		CGColorSpaceRelease(colorspace);
	}

	if (*success) {
		_startTime = -1.;
		_eventQueue = [NSMutableArray new];
		_resultParameters = [NSMutableDictionary new];	
		pthread_mutex_init(&_eventMutex, NULL);
		pthread_mutex_init(&_resultParametersMutex, NULL);
		pthread_mutex_init(&_executionMutex, NULL);

		pthread_cond_broadcast((pthread_cond_t*)[[(NSDictionary*)userInfo valueForKey:@"condition"] pointerValue]);
		pthread_mutex_unlock((pthread_mutex_t*)[[(NSDictionary*)userInfo valueForKey:@"mutex"] pointerValue]);
		
		//Create a timer which will regularly call our processing method
		_timer = [[NSTimer timerWithTimeInterval:(fps ? 1./fps: 0.) target:self selector:@selector(_processComposition:) userInfo:nil repeats:YES] retain];
		[[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];			
			
		pthread_mutex_lock(&_executionMutex);
		do
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
		while (_isRunning);
		pthread_mutex_unlock(&_executionMutex);
		
		pthread_mutex_lock(&_eventMutex);
		[_eventQueue release];
		_eventQueue = nil;
		pthread_mutex_unlock(&_eventMutex);
		
		pthread_mutex_lock(&_resultParametersMutex);
		[_resultParameters release];
		_resultParameters = nil;
		[_renderer release];			// In lock to avoid setResultOnRenderer method still executing
		_renderer = nil;
		pthread_mutex_unlock(&_resultParametersMutex);
		
		pthread_mutex_destroy(&_resultParametersMutex);
		pthread_mutex_destroy(&_eventMutex);
		pthread_mutex_destroy(&_executionMutex);
	}
	else {
		pthread_cond_broadcast((pthread_cond_t*)[[(NSDictionary*)userInfo valueForKey:@"condition"] pointerValue]);
		pthread_mutex_unlock((pthread_mutex_t*)[[(NSDictionary*)userInfo valueForKey:@"mutex"] pointerValue]);	
	}
	
	[pool release];
}

- (void) stop
{
	_isRunning = NO;
	[_timer invalidate];
}

- (void) queueEvent:(NSEvent *)event mouseLocation:(NSPoint)mouseLocation
{
	NSMutableDictionary*					arguments = [NSMutableDictionary dictionary];
		
	//We setup the arguments to pass to the composition (normalized mouse coordinates and an optional event)
	if (mouseLocation.x && mouseLocation.y)
	[arguments setObject:[NSValue valueWithPoint:mouseLocation] forKey:QCRendererMouseLocationKey];
	if(event)
	[arguments setObject:event forKey:QCRendererEventKey];
	
	pthread_mutex_lock(&_eventMutex);
	[_eventQueue addObject:arguments];
	pthread_mutex_unlock(&_eventMutex);
}

- (void) setResultsOnRenderer:(QCRenderer*)renderer
{
	NSArray*			outputKeys,
						*rendererKeys = [renderer inputKeys];
	NSUInteger			i;
	NSString*			key;
	
	pthread_mutex_lock(&_resultParametersMutex);
	outputKeys = [_renderer outputKeys];
	for (i=0; i<[outputKeys count]; ++i) {
	    key = [outputKeys objectAtIndex:i];
		if ([rendererKeys indexOfObject:key] != NSNotFound) {
			if(![renderer setValue:[_resultParameters valueForKey:key] forInputKey:key])
			NSLog (@"Could not set value for key: %@", key);
		}
	} 	
	pthread_mutex_unlock(&_resultParametersMutex);
}

- (void) broadcastResultsUsingHost:(Host*)host
{
	pthread_mutex_lock(&_resultParametersMutex);
	[host broadcastMasterCompositionData:_resultParameters];
	pthread_mutex_unlock(&_resultParametersMutex);
}

- (void) setTime:(NSTimeInterval)newTime
{
	NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate] - _startTime;
	
	_startTime += (time - newTime);
}

@end
