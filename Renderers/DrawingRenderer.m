#import <OpenGL/CGLMacro.h>
#import "DrawingRenderer.h"
#import "Utils.h"

//CLASS INTERFACE:

@interface DrawingRenderer(Internal)
- (void) _renderScene;
@end

//FUNCTIONS:

static CVReturn _displayLinkCallBack(CVDisplayLinkRef displayLink, const CVTimeStamp* inNow, const CVTimeStamp* inOutputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext)
{
	DrawingRenderer*			renderer = displayLinkContext;
	NSAutoreleasePool*			pool;
	
	//Create an autorelease pool (necessary to call Obj-C code from non-Obj-C code)
	pool = [NSAutoreleasePool new];
	//Simply ask the application controller to render and display a new frame
	[renderer _renderScene];
	//Destroy the autorelease pool
	[pool release];
	
	return kCVReturnSuccess;
}

//CLASS IMPLEMENTATION:

@implementation DrawingRenderer

+ (GLint) rendererIDForDisplayID:(CGDirectDisplayID)displayID
{
	GLint									rendererID = 0,
											count,
											i,
											value;
	CGLRendererInfoObj						info;
	
	if(CGLQueryRendererInfo(CGDisplayIDToOpenGLDisplayMask(displayID), &info, &count) == kCGLNoError) {
		for(i = 0; i < count; ++i) {
			if((CGLDescribeRenderer(info, i, kCGLRPAccelerated, &value) == kCGLNoError) && value) {
				CGLDescribeRenderer(info, i, kCGLRPRendererID, &rendererID);
				break;
			}
		}
		CGLDestroyRendererInfo(info);
	}
	
	return rendererID;
}

- (id) initWithComposition:(QCComposition*)composition screen:(Screen*)screen renderFrame:(NSRect)renderFrame withProcessingRenderer:(ProcessingRenderer*)processor options:(NSDictionary*)options
{
	BOOL									useFullScreen = ![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_DisableFullScreen],
											useDisplayLink = ![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_DisableDisplayLink];
	NSOpenGLPixelFormatAttribute			attributes[] = {NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask([screen displayID]), NSOpenGLPFAAccelerated, /*NSOpenGLPFANoRecovery,*/ NSOpenGLPFADoubleBuffer, /*NSOpenGLPFAColorSize, 32,*/ NSOpenGLPFADepthSize, 24, 0, 0};
	NSOpenGLPixelFormat*					pixelFormat;
	float									maxSide = 0.0;
	NSPoint									center;
	CGColorSpaceRef							colorspace;
	NSUInteger								screenBezel;
	CGRect									bounds;
	GLint									swapInterval = 1;
											
	maxSide = MAX(renderFrame.size.width, renderFrame.size.height);
	center = NSMakePoint(renderFrame.size.width/2., renderFrame.size.height/2.);

	_screenFrame = [screen frame];
	if ((screenBezel = [[options valueForKey:kDrawingRendererOptionsKey_ScreenBezel] intValue]))
	_screenFrame = NSMakeRect(_screenFrame.origin.x + screenBezel, _screenFrame.origin.y + screenBezel, _screenFrame.size.width - 2*screenBezel, _screenFrame.size.height - 2*screenBezel);
		
	_subRegion = _screenFrame;
	_subRegion.origin.x = (_subRegion.origin.x + maxSide/2. - renderFrame.size.width/2. + _subRegion.size.width/2.) / maxSide ;
	_subRegion.origin.y = (_subRegion.origin.y + maxSide/2. - renderFrame.size.height/2. + _subRegion.size.height/2.) / maxSide ;
	_subRegion.size.width /= maxSide;
	_subRegion.size.height /= maxSide;	

	_displayID = [screen displayID];
	
	if(useFullScreen)
	attributes[sizeof(attributes) / sizeof(NSOpenGLPixelFormatAttribute) - 2] = NSOpenGLPFAFullScreen;
	pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attributes] autorelease];
	if (!pixelFormat) {
		NSLog(@"Failed creating pixelFormat");
		[self release];
		return nil;
	}
	[pixelFormat getValues:&_rendererID forAttribute:NSOpenGLPFARendererID forVirtualScreen:0]; //Virtual screen #0 should be the HW renderer
	
	_glContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:[options objectForKey:kDrawingRendererOptionsKey_ShareContext]];
	if (!_glContext) {
		NSLog(@"Failed creating context");
		[self release];
		return nil;
	}
	if([[options objectForKey:kDrawingRendererOptionsKey_VBLSyncing] boolValue])
	[_glContext setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
	if(useFullScreen)
	[_glContext setFullScreen];
	
	colorspace = (CGColorSpaceRef)CGDisplayCopyColorSpace(_displayID);
	if(colorspace == NULL) {
		NSLog(@"Failed creating CGColorSpace");
		CGColorSpaceRelease(colorspace);
		[self release];
		return nil;
	}	
	
	if(useFullScreen == NO) {
		bounds = CGDisplayBounds([screen displayID]);
		bounds.origin.y = CGDisplayBounds(kCGDirectMainDisplay).size.height - bounds.size.height - bounds.origin.y;
		bounds.size.width /= 2;
		bounds.size.height /= 2;
		_window = [[NSWindow alloc] initWithContentRect:*((NSRect*)&bounds) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
		if (!_window) {
			NSLog(@"Failed creating fullScreenWindow");
			[self release];
			return nil;
		}
		[_window setLevel:NSScreenSaverWindowLevel];
		[_window setOpaque:YES];
		[_window setHasShadow:NO];
		
		[_window makeKeyAndOrderFront:nil];
		[_glContext setView:[_window contentView]];
		NSLog(@"WARNING: Using window instead of full-screen OpenGL context");
	}
	
	self = [super initWithCGLContext:[_glContext CGLContextObj] pixelFormat:[pixelFormat CGLPixelFormatObj] colorSpace:colorspace composition:composition];
	if (self) {
		CGColorSpaceRelease(colorspace);
		_startTime = -1;
		if ([[self inputKeys] indexOfObject:@"screenCoordinates"] != NSNotFound)
			[self setValue:[NSDictionary dictionaryWithObjectsAndKeys:
													_RectToArray(renderFrame), @"renderRect",
													_RectToArray(_screenFrame), @"subRegionRect", nil]
					forInputKey:@"screenCoordinates"];
		
		if (processor)
			_processorRenderer = [processor retain];
		else {
			pthread_mutex_init(&_eventMutex, NULL);
			_eventQueue = [NSMutableArray new];
		}
		
		if(useDisplayLink) {
			// We create the display link that will call our callback 
			if(CVDisplayLinkCreateWithOpenGLDisplayMask(CGDisplayIDToOpenGLDisplayMask(_displayID), &_displayLink) == kCVReturnSuccess) {
				CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, [_glContext CGLContextObj], [pixelFormat CGLPixelFormatObj]);
				CVDisplayLinkSetOutputCallback(_displayLink, _displayLinkCallBack, self);
			}
			else {
				NSLog(@"Failed creating displayLink");
				[self release];
				return nil;
			}
		}
		else {
			_timer = [[NSTimer alloc] initWithFireDate:nil interval:(1.0 / 60.0) target:self selector:@selector(_renderTimer:) userInfo:nil repeats:YES];
			if(_timer == nil) {
				NSLog(@"Failed creating timer");
				[self release];
				return nil;
			}
			[self release]; //HACK: NSTimer retains its target so this creates a retain-loop
			[[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
			NSLog(@"WARNING: Using NSTimer on main thread instead of CVDisplayLink");
		}
		
		if(useFullScreen) {
			CGDisplayCapture(_displayID);
			CGDisplayHideCursor(_displayID);
		}
		
		if(useDisplayLink)
		CVDisplayLinkStart(_displayLink);
	}
	else {
		[_window release];
		[_glContext clearDrawable];
		[_glContext release];
	}
	
	return self;
}

- (void) dealloc
{
	if(_displayLink) {
		CVDisplayLinkStop(_displayLink);
		CVDisplayLinkRelease(_displayLink);
	}
	if(_displayID) {
		CGDisplayRelease(_displayID);
		CGDisplayShowCursor(_displayID);	
	}
	
	if(_timer) {
		[self retain]; //HACK: NSTimer retains its target so this creates a retain-loop
		[_timer invalidate];
		[_timer release];
	}
	[_window release];
	
	[_glContext release];

	if(_processorRenderer)
	[_processorRenderer release];
	else {
		pthread_mutex_destroy(&_eventMutex);
		[_eventQueue release];
	}
	
	[super dealloc];
}

- (NSOpenGLContext*) openGLContext
{
	return _glContext;
}

- (GLint) rendererID
{
	return _rendererID;
}

// FIXME: Transform mouse coordinates appropriately in case no processing renderers and multiple displays without network
- (void) queueEvent:(NSEvent *)event
{
	NSPoint									mouseLocation;
	NSMutableDictionary*					arguments;
	
	/* To be implement: Transform mouseLocation */
		
	arguments = [NSMutableDictionary dictionaryWithObject:[NSValue valueWithPoint:mouseLocation] forKey:QCRendererMouseLocationKey];
	if(event)
	[arguments setObject:event forKey:QCRendererEventKey];
	
	pthread_mutex_lock(&_eventMutex);
	[_eventQueue addObject:arguments];
	pthread_mutex_unlock(&_eventMutex);
}

- (void) _renderScene
{
	CGLContextObj		cgl_ctx = [_glContext CGLContextObj];
	float				scale = MIN(1. / _subRegion.size.width, 1. / _subRegion.size.height);
	NSTimeInterval		time;
	NSUInteger			argCount;
	NSDictionary*		arguments = nil;

	if (_startTime < 0)
		_startTime = [NSDate timeIntervalSinceReferenceDate];
	time = [NSDate timeIntervalSinceReferenceDate] - _startTime;

	// Forward outputValues from processorRenderer to this drawingRenderer inputs
	if (_processorRenderer)
	[(ProcessingRenderer*)_processorRenderer setResultsOnRenderer:self];
	else {
		// Remove last event from the queue if any
		pthread_mutex_lock(&_eventMutex);
		argCount = [_eventQueue count];
		if (argCount) {
			arguments = [[_eventQueue objectAtIndex:argCount-1] retain];
			[_eventQueue removeObjectAtIndex:argCount-1];
		}
		pthread_mutex_unlock(&_eventMutex);
	}
	
	glClearColor(0.0f, 0.0, 0.0, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glPushMatrix();
	// Translate and scale the projection matrix so that correct subregion is rendered on display
	glTranslatef( (0.5 - _subRegion.origin.x) / _subRegion.size.width * 2.0, (0.5 - _subRegion.origin.y) / _subRegion.size.height * 2.0, 0.0);
	glScalef(scale, scale, 1.0);
	
	// Render composition
	if (![super renderAtTime:time arguments:arguments])
	NSLog(@"%@: Rendering failed at time %.3fs", self);
	else	
	[_glContext flushBuffer];
	
	// Restore projection matrix
	glMatrixMode(GL_PROJECTION);
	glPopMatrix();
}

- (void) _renderTimer:(NSTimer*)timer
{
	[self _renderScene];
}

- (void) setTime:(NSTimeInterval)newTime
{
	NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate] - _startTime;
	
	_startTime += (time - newTime);
}

@end

