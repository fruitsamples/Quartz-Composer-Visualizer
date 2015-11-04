#import <OpenGL/CGLMacro.h>

#import "MyApplication.h"
#import "Utils.h"

// CONSTANTS:

#if __FULL_SCREEN_CONTEXT__
#define kEventMask ( NSLeftMouseDownMask | NSLeftMouseDraggedMask | NSLeftMouseUpMask | NSRightMouseDownMask | NSRightMouseDraggedMask | NSRightMouseUpMask | NSOtherMouseDownMask | NSOtherMouseUpMask | NSOtherMouseDraggedMask | NSKeyDownMask | NSKeyUpMask | NSFlagsChangedMask | NSScrollWheelMask | NSTabletPointMask | NSTabletProximityMask)
#define kMouseEventMask ( NSLeftMouseDownMask | NSLeftMouseDraggedMask | NSLeftMouseUpMask | NSRightMouseDownMask | NSRightMouseDraggedMask | NSRightMouseUpMask | NSOtherMouseDownMask | NSOtherMouseUpMask | NSOtherMouseDraggedMask | NSFlagsChangedMask | NSScrollWheelMask | NSTabletPointMask | NSTabletProximityMask)
#else
#define kEventMask (0)
#define kMouseEventMask (0)
#endif
#define kDefaultProcessingFramerate 60.0
#define kDefaultTimeSyncFramerate 120.0

#define kDefaultHeight 290
#define kAdvandedSettingsHeight 270
#define kHostPaneHeight 750
#define kClientPaneHeight 296
#define kMaxHeight 1000

#define kScreensKey							@"qcVisualizer.screens"
#define kProcessingFramerateKey				@"qcVisualizer.processingFramerate"
#define kTimeSyncFramerateKey				@"qcVisualizer.timeSyncFramerate"
#define kUseNetworkKey						@"qcVisualizer.useNetwork"
#define kHostTypeKey						@"qcVisualizer.hostType"
#define kUseVBLKey							@"qcVisualizer.useVBL"
#define kMasterProcessingCompositionKey		@"qcVisualizer.master"
#define kDoNotRunOnMasterKey				@"qcVisualizer.doNotRunOnMaster"
#define kScreenBezelKey						@"qcVisualizer.screenBezel"
#define kUseBezelKey						@"qcVisualizer.useBezel"

//CLASS DEFINITIONS:

@interface MyApplication(KVC)
- (void) setDrawingCompositionPath:(NSString*)path;
- (void) setProcessingCompositionPath:(NSString*)path;
@end

// IMPLEMENTATIONS:

@implementation MyApplication

- (void) resetScreens
{
	// Reinitialize screen configuration
	[_screens removeAllScreens];
	[_screens setNSScreens:[NSScreen screens] forKey:_hostName];
	if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
	[qcView setValue:[_screens flatten] forInputKey:@"screens"];
}

- (void) _updateScreens:(NSNotification*)notification
{ // FIXME: Send to server when client changes screen configuration
	[self resetScreens];
	if (_server)
	[_server broadcastScreenConfiguration:_screens];
}

- (void) _broadcastHostData:(id)userInfo
{
	NSTimeInterval		time;

	if (_hostStartTime < 0)
	_hostStartTime = [NSDate timeIntervalSinceReferenceDate];
	time = [NSDate timeIntervalSinceReferenceDate] - _hostStartTime;
	
	[_server broadcastTime:time];	
	[self setTime:time];
	if (!_distributeProcessingComposition)
	[_processorRenderer broadcastResultsUsingHost:_server];
}

- (void) _broadcastAppParameters
{
	[_server broadcastApplicationParameters:[NSDictionary dictionaryWithObjectsAndKeys:
											[NSNumber numberWithBool:_vblSync], @"vblSync",
											[NSNumber numberWithDouble:_timeSyncFramerate], @"timeSyncFramerate",
											[NSNumber numberWithDouble:_maxProcessingFramerate], @"maxProcessingFramerate",
											[NSNumber numberWithBool:_distributeProcessingComposition], @"distributeProcessingComposition",
											[NSNumber numberWithBool:_useBezel], @"useBezel",
											[NSNumber numberWithInt:_screenBezel], @"screenBezel",
											nil]];
}

- (void) addClient:(NSString*)name screens:(NSArray*)screens
{
	[_screens setScreens:screens forKey:name];

	if (_server) {		// FIXME: should only send to new client
		// Broadcast current host configuration to new client
		[_server broadcastScreenConfiguration:_screens];
		if (_processingCompositionData && _distributeProcessingComposition)
		[_server broadcastProcessingComposition:_processingCompositionData];
		if (_drawingCompositionData)
		[_server broadcastDrawingComposition:_drawingCompositionData];
		[self _broadcastAppParameters];
		if (_isRunning)
		[_server broadcastPlay];
	}
	
	if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
	[qcView setValue:[_screens flatten] forInputKey:@"screens"];
	[tableView reloadData];
}

- (void) removeClient:(NSString*)name
{
	[_screens removeScreensForKey:name];	

	if (_server)
	[_server broadcastScreenConfiguration:_screens];
	
	if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
	[qcView setValue:[_screens flatten] forInputKey:@"screens"];
	
	[tableView reloadData];
}

- (id) init
{
	NSData*			data;
	
	//We need to be our own delegate
	self = [super init];
	if(self) {
		[self setDelegate:self];
		_drawingRenderers = [NSMutableArray new];
				
		_hostStartTime = -1;
		_hostName = [(id)CSCopyMachineName() retain];
		_maxProcessingFramerate = [[NSUserDefaults standardUserDefaults] integerForKey:kProcessingFramerateKey] ? [[NSUserDefaults standardUserDefaults] integerForKey:kProcessingFramerateKey] : kDefaultProcessingFramerate;
		_timeSyncFramerate = [[NSUserDefaults standardUserDefaults] integerForKey:kTimeSyncFramerateKey] ? [[NSUserDefaults standardUserDefaults] integerForKey:kTimeSyncFramerateKey] : kDefaultTimeSyncFramerate;
		_vblSync = [[NSUserDefaults standardUserDefaults] boolForKey:kUseVBLKey];
		_distributeProcessingComposition = [[NSUserDefaults standardUserDefaults] boolForKey:kMasterProcessingCompositionKey];
		_useBezel = [[NSUserDefaults standardUserDefaults] integerForKey:kUseBezelKey];
		_screenBezel = [[NSUserDefaults standardUserDefaults] integerForKey:kScreenBezelKey];
		_hostType = -1;
		
		data = [[NSUserDefaults standardUserDefaults] dataForKey:kScreensKey];
		_screens = [Screens new];
		if (data)
		[_screens setSavedScreens:(Screens*)[NSKeyedUnarchiver unarchiveObjectWithData:data]];
		[_screens setNSScreens:[NSScreen screens] forKey:_hostName];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateScreens:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
	}
		
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
	[_drawingRenderers release];
	[_processorRenderer release];
	[_processingCompositionPath release];
	[_drawingCompositionPath release];
	[_processingComposition release];
	[_drawingComposition release];
	[_processingCompositionData release];
	[_drawingCompositionData release];
	[_screens release];
	[_hostName release];
	
	[super dealloc];
}

- (void) _reset
{
	[_drawingRenderers removeAllObjects];
	[_processorRenderer release];
}

- (void) awakeFromNib
{
	[self _reset];
	
	[qcView loadCompositionFromFile:[[NSBundle mainBundle] pathForResource:@"VisualizationPreview" ofType:@"qtz"]];
	[qcView setValue:[[NSBundle mainBundle] pathForResource:@"SelectCompositionText" ofType:@"qtz"] forInputKey:@"path"];
	[qcView setValue:[_screens flatten] forInputKey:@"screens"];
	[settingsBox setHidden:YES];
	[self setValue:[NSNumber numberWithBool:NO] forKey:@"isRunning"];

	[self setValue:[NSNumber numberWithInteger:[[NSUserDefaults standardUserDefaults] integerForKey:kHostTypeKey]] forKey:@"hostType"];
	[self setValue:[NSNumber numberWithBool:[[NSUserDefaults standardUserDefaults] boolForKey:kDoNotRunOnMasterKey]] forKey:@"doNotRunCompositionOnMaster"];
}

- (BOOL) application:(NSApplication*)sender openFile:(NSString*)filename
{
	[self setValue:[filename stringByStandardizingPath] forKey:@"drawingCompositionPath"];
	
	if([[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_AutoStart])
	[self play:nil];
	
	return YES;
}

- (void) windowWillClose:(NSNotification*)notification
{
	[NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	if (_server) {
		[_server broadcastScreenConfiguration:nil];
		[_server broadcastDrawingComposition:nil];
		if (_isRunning)
		[_server broadcastStop];
	}
	[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:_screens] forKey:kScreensKey];
	[[NSUserDefaults standardUserDefaults] setBool:_vblSync forKey:kUseVBLKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_hostType forKey:kHostTypeKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_timeSyncFramerate forKey:kTimeSyncFramerateKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_maxProcessingFramerate forKey:kProcessingFramerateKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_distributeProcessingComposition forKey:kMasterProcessingCompositionKey];
	[[NSUserDefaults standardUserDefaults] setBool:_doNotRunCompositionOnMaster forKey:kDoNotRunOnMasterKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_screenBezel forKey:kScreenBezelKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_useBezel forKey:kUseBezelKey];
}

- (void) sendEvent:(NSEvent*)event
{
	NSUInteger			i;
	NSRect				frame;
	NSPoint				mouseLocation = NSZeroPoint;
	
	//Add events to the processor event queue (if processor renderer exists), if not to the dawing renderers.
	if (_isRunning) {
		//If the user pressed the [Esc] key, we need to exit
		if(([event type] == NSKeyDown) && ([event keyCode] == 0x35)) 
		[self stop:self];
		else if (NSEventMaskFromType([event type]) & kEventMask) {
			if (NSEventMaskFromType([event type]) & kMouseEventMask) {
				if (_doNotRunCompositionOnMaster && _server) { 
					if ([event window] == [qcView window]) { // Only get event contained in the QCView frame
						mouseLocation = [event locationInWindow];
						frame = [[qcView window] frame]; // Convert to qcView coordinates
						mouseLocation.x = mouseLocation.x / frame.size.width;
						mouseLocation.y = mouseLocation.y / frame.size.height;					
					}
					else {
						[super sendEvent:event];
						return;
					}
				}
				else 
				event = nil; // No mouse control when not processor running on host only and not rendering
			}

			//Queue event to processor or drawing renderers (if no processor, i.e. not in processing/drawing mode)
			if (event) {
				if(_processorRenderer) 
				[_processorRenderer queueEvent:event mouseLocation:mouseLocation];
				else if (_doNotRunCompositionOnMaster && _server)
				[super sendEvent:event];
				else {
					for (i=0; i<[_drawingRenderers count]; ++i)
					[(DrawingRenderer*)[_drawingRenderers objectAtIndex:i] queueEvent:event];
				}
			}
		}
	}
	else
	[super sendEvent:event];
}

- (IBAction) loadDrawingComposition:(id)sender
{
	NSOpenPanel*							openPanel = [NSOpenPanel openPanel];

	/* Load drawing composition if necesserary */
	[openPanel setTitle:@"Select Rendering Composition"];
	if([openPanel runModalForTypes:[NSArray arrayWithObject:@"qtz"]] == NSFileHandlingPanelOKButton)
		[self setValue:[openPanel filename] forKey:@"drawingCompositionPath"];
}

- (IBAction) loadProcessingComposition:(id)sender
{
	NSOpenPanel*							openPanel = [NSOpenPanel openPanel];

	/* Load processing composition if necesserary */
	[openPanel setTitle:@"Select Processing Composition"];
	if ([openPanel runModalForTypes:[NSArray arrayWithObject:@"qtz"]] == NSFileHandlingPanelOKButton) {
		[self setValue:[openPanel filename] forKey:@"processingCompositionPath"];
	}
}

- (void) setCompositionPath:(NSString*)path iconView:(IconView*)sender;
{
	if ((sender == processingCompositionIconView) || (sender == processingCompositionIconViewHost))
	[self setProcessingCompositionPath:path];
	else
	[self setDrawingCompositionPath:path];
}

- (IBAction) stop:(id)sender
{
	if (_isRunning) {
		if(_activityTimer) {
			CFRunLoopTimerInvalidate(_activityTimer);
			CFRelease(_activityTimer);
			_activityTimer = NULL;
		}
		
		[self setValue:[NSNumber numberWithBool:NO] forKey:@"isRunning"];			
		
		if (_server) {
			[_server broadcastStop];
			[_hostTimer invalidate];
		}
		
		//Release processor if any
		if (_processorRenderer) {
			[_processorRenderer stop];
			[_processorRenderer release];
			_processorRenderer = nil;
		}
		
		if (!_doNotRunCompositionOnMaster || !_server) {
			//Release drawing renderers
			[_drawingRenderers removeAllObjects];

			// Restart the preview view
			[qcView loadCompositionFromFile:[[NSBundle mainBundle] pathForResource:@"VisualizationPreview" ofType:@"qtz"]];
			
			[qcView setValue:[_screens flatten] forInputKey:@"screens"];
			if ((_selectedRow >= 0) && [[_server clients] count])
			[qcView setValue:[[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0] forInputKey:@"selected"];
			else
			[qcView setValue:nil forInputKey:@"selected"];
			
			if (_drawingCompositionPath)
			[qcView setValue:_drawingCompositionPath forInputKey:@"path"];
			else
			[qcView setValue:[[NSBundle mainBundle] pathForResource:@"SelectCompositionText" ofType:@"qtz"] forInputKey:@"path"];
			
			[qcView startRendering];
		}
	}
}

static void _ActivityTimerCallback(CFRunLoopTimerRef timer, void* info)
{
	UpdateSystemActivity(OverallAct);
}

- (IBAction) play:(id)sender
{
	NSArray*								screens = [_screens screensForKey:_hostName];
	DrawingRenderer*						renderer;
	NSUInteger								i,
											j;
	NSMutableDictionary*					options;
	CFRunLoopTimerContext					context = {0, NULL, NULL, NULL, NULL};
	GLint									rendererID;
	
	if (!_isRunning) {
		options = [NSMutableDictionary new];
		
		if (_processingComposition) {
			_processorRenderer = [[ProcessingRenderer alloc] initWithComposition:_processingComposition framerate:_maxProcessingFramerate];
			if(!_processorRenderer) {
				[self _reset];
				[[NSAlert alertWithMessageText:@"Can not load processing composition" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"Incorrect file or not a processing composition. Please select another file."] runModal];
				return;
			}
		}
		
		if (_drawingComposition) {
			if (_vblSync)
			[options setObject:[NSNumber numberWithBool:_vblSync] forKey:kDrawingRendererOptionsKey_VBLSyncing];
			if (_useBezel && _screenBezel)
			[options setObject:[NSNumber numberWithUnsignedInt:_screenBezel] forKey:kDrawingRendererOptionsKey_ScreenBezel];				
			
			if (!_doNotRunCompositionOnMaster || !_server) {
				for (i=0; i<[screens count]; ++i) {
					// If two or more DrawingRenderers use the same OpenGL renderer, make sure to share their OpenGL context to ensure optimal Quartz Composer performances
					rendererID = [DrawingRenderer rendererIDForDisplayID:[[screens objectAtIndex:i] displayID]];
					for(j = 0; j < i; ++j) {
						renderer = [_drawingRenderers objectAtIndex:j];
						if([renderer rendererID] == rendererID) {
							[options setObject:[renderer openGLContext] forKey:kDrawingRendererOptionsKey_ShareContext];
							NSLog(@"Sharing OpenGL contexts between drawing renderers #%i and #%i", i, j);
							break;
						}
					}
					
					renderer = [[DrawingRenderer alloc] initWithComposition:_drawingComposition screen:[screens objectAtIndex:i] renderFrame:[_screens renderFrame] withProcessingRenderer:((_client && !_distributeProcessingComposition) ? (ProcessingRenderer*)self : _processorRenderer) options:options];
					if(!renderer) {
						[self _reset];
						[options release];
						[[NSAlert alertWithMessageText:@"Can not load drawing composition" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:[NSString stringWithFormat:@"Can not create drawing renderer for screen %i.\n", i]] runModal];
						return;
					}
					[_drawingRenderers addObject:renderer];
					[renderer release];
					
					[options removeObjectForKey:kDrawingRendererOptionsKey_ShareContext];
				}
				[qcView stopRendering];
				[qcView unloadComposition];
				[self setValue:[NSNumber numberWithBool:YES] forKey:@"isRunning"];			
			}
			
			if ([_server hasClients]) {
				[_server broadcastPlay];
				_hostTimer = [[NSTimer timerWithTimeInterval:1/_timeSyncFramerate target:self selector:@selector(_broadcastHostData:) userInfo:nil repeats:YES] retain];
				[_hostTimer fire];
				[[NSRunLoop currentRunLoop] addTimer:_hostTimer forMode:NSRunLoopCommonModes];			
				[self setValue:[NSNumber numberWithBool:YES] forKey:@"isRunning"];			
			}
		}

		[options release];
		
		_activityTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), 30.0, 0, 0, _ActivityTimerCallback, &context);
		if(_activityTimer)
		CFRunLoopAddTimer(CFRunLoopGetCurrent(), _activityTimer, kCFRunLoopCommonModes);
	}
}

- (void) _restart
{
	[self stop:self];
	[self play:self];
}

- (IBAction) moveLeft:(id)sender
{
	NSString*		key;
	
	if ((_selectedRow>=0) && (key = [[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0])) {
		[_screens moveLeftForKey:key];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:[_screens flatten] forInputKey:@"screens"];
		if (_server)
		[_server broadcastScreenConfiguration:_screens];
	}
}

- (IBAction) moveRight:(id)sender
{
	NSString*		key;
	
	if ((_selectedRow>=0) && (key = [[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0])) {
		[_screens moveRightForKey:key];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:[_screens flatten] forInputKey:@"screens"];
		if (_server)
		[_server broadcastScreenConfiguration:_screens];
	}
}

- (IBAction) moveUp:(id)sender
{
	NSString*		key;
	
	if ((_selectedRow>=0) && (key = [[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0])) {
		[_screens moveUpForKey:key];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:[_screens flatten] forInputKey:@"screens"];
		if (_server)
		[_server broadcastScreenConfiguration:_screens];
	}
}

- (IBAction) moveDown:(id)sender
{
	NSString*		key;
	
	if ((_selectedRow>=0) && (key = [[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0])) {
		[_screens moveDownForKey:key];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:[_screens flatten] forInputKey:@"screens"];
		if (_server)
		[_server broadcastScreenConfiguration:_screens];
	}
}

- (void) setTime:(NSTimeInterval)time
{
	NSUInteger i;
	
	if (_processorRenderer)
	[_processorRenderer setTime:time];
	
	for (i=0; i<[_drawingRenderers count]; ++i)
	[(DrawingRenderer*)[_drawingRenderers objectAtIndex:i] setTime:time];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*)tableView
{
	return [[_server clients] count];
}

- (id) tableView:(NSTableView*)tableView objectValueForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
	if ([[tableColumn identifier] isEqualToString:@"name"])
	return [[[_server clients] objectAtIndex:row] objectAtIndex:0];
	else if ([[tableColumn identifier] isEqualToString:@"active"])
	return [NSNumber numberWithBool:[(Connection*)[[[_server clients] objectAtIndex:row] objectAtIndex:1] active]];
	
	return nil;
}

- (void) updateTableView
{
	[tableView reloadData];
}

- (IBAction) setSelected:(id)sender
{
	_selectedRow = [tableView selectedRow];

	if (!_isRunning || (_doNotRunCompositionOnMaster && _server)) {
		if (_selectedRow >= 0)
		[qcView setValue:[[[_server clients] objectAtIndex:_selectedRow] objectAtIndex:0] forInputKey:@"selected"];
		else
		[qcView setValue:nil forInputKey:@"selected"];
	}
}

- (IBAction) setActive:(id)sender
{
	NSUInteger			i;
	
	if (_isRunning && _server)
	[self stop:self];
	
	for (i=0; i<[[_server clients] count]; ++i)
	[_server setActive:([[sender preparedCellAtColumn:0 row:i] state] == NSOnState) forClientAtIndex:i];
	
	if (_isRunning && _server)
	[self play:self];
}

@end

@implementation MyApplication (KVC)

//FIXME: Clean-up
- (void) setDecoupledCompositions:(NSNumber*)value
{
	BOOL	booValue = [value boolValue];
	
	if (!booValue) {
		[self setValue:@"" forKey:@"processingCompositionPath"];
		[_processorRenderer release];
		_processorRenderer = nil;
	}
	_decoupledCompositions = booValue;
}

- (NSString*) processingCompositionFileName
{
	return [[_processingComposition attributes] objectForKey:QCCompositionAttributeNameKey];
}

- (NSString*) drawingCompositionFileName
{
	return [[_drawingComposition attributes] objectForKey:QCCompositionAttributeNameKey];
}

- (void) setDrawingCompositionPath:(NSString*)path
{
	if (_drawingCompositionPath != path) {
		[self willChangeValueForKey:@"drawingCompositionFileName"];

		[_drawingCompositionPath release];
		[_drawingCompositionData release];
		[_drawingComposition release];
		_drawingCompositionPath = [path retain];
		_drawingCompositionData = (path ? [[NSData alloc] initWithContentsOfFile:path] : nil);
		_drawingComposition = (_drawingCompositionData ? [[QCComposition compositionWithData:_drawingCompositionData] retain] : nil); //FIXME: Check composition has consumers using QCCompositionAttributeHasConsumersKey 
				
		if (_server) 
		[_server broadcastDrawingComposition:_drawingCompositionData];
		
		[drawingCompositionIconView setImage:(path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil)];
		[drawingCompositionIconViewHost setImage:(path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil)];

		[self didChangeValueForKey:@"drawingCompositionFileName"];

		if (_isRunning && _server)
		[self _restart];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:_drawingCompositionPath forInputKey:@"path"];		
	}
}

- (void) setProcessingCompositionPath:(NSString*)path
{
	if (_processingCompositionPath != path) {
		[self willChangeValueForKey:@"processingCompositionFileName"];
		
		[_processingCompositionPath release];
		[_processingComposition release];
		[_processingCompositionData release];
		_processingCompositionPath = [path retain];
		_processingCompositionData = (path ? [[NSData alloc] initWithContentsOfFile:path] : nil);
		_processingComposition = (_processingCompositionData ? [[QCComposition compositionWithData:_processingCompositionData] retain] : nil);
		
		if (_server && _distributeProcessingComposition) 
		[_server broadcastProcessingComposition:_processingCompositionData];
		
		[processingCompositionIconView setImage:(path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil)];
		[processingCompositionIconViewHost setImage:(path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil)];

		[self didChangeValueForKey:@"processingCompositionFileName"];

		if (_isRunning && _server)
		[self _restart];
	}
}

- (void) setDrawingCompositionData:(NSData*)data
{
	if (data != _drawingCompositionData) {
		[self willChangeValueForKey:@"drawingCompositionFileName"];

		[_drawingCompositionData release];
		[_drawingComposition release];
		[_drawingCompositionPath release];
		_drawingCompositionPath = nil;
		if (data) {
			_drawingCompositionData = [data retain];
			_drawingComposition = [[QCComposition compositionWithData:_drawingCompositionData] retain];
//FIXME: HACK: For qcView to display something
			_drawingCompositionPath = @"/tmp/qcVisualizerDrawingCompositionTmp.qtz";
			if (![_drawingCompositionData writeToFile:_drawingCompositionPath atomically:NO])
			NSLog(@"Failed writing temporary composition file");
			else if (!_isRunning || (_doNotRunCompositionOnMaster && _server)) {
				[qcView setValue:_drawingCompositionPath forInputKey:@"path"];
				[qcView stopRendering];
				[qcView startRendering]; //Force to reload file
			}			
		}
		else {
			_drawingComposition = nil;
			_drawingCompositionData = nil;
			if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
			[qcView setValue:[[NSBundle mainBundle] pathForResource:@"SelectCompositionText" ofType:@"qtz"] forInputKey:@"path"];			
		}
		
		[self didChangeValueForKey:@"drawingCompositionFileName"];

		if (_isRunning && _server)
		[self _restart];
	}
}

- (void) setProcessingCompositionData:(NSData*)data
{
	if (data != _drawingCompositionData) {
		[self willChangeValueForKey:@"processingCompositionFileName"];

		[_processingCompositionData release];
		[_processingComposition release];
		
		if (data) {
			_processingCompositionData = [data retain];
			_processingComposition = [[QCComposition compositionWithData:_processingCompositionData] retain];
		}
		else {
			_processingCompositionData = nil;
			_processingComposition = nil;
		}
		
		[self didChangeValueForKey:@"processingCompositionFileName"];

		if (_isRunning && _server)
		[self _restart];
	}
}

- (void) setHostType:(NSUInteger)index
{
	NSRect		frame = [window frame];

	if (_hostType != index) {
		_hostType = index;
		[self resetScreens];
		if (index == 0) {
			if (_client) {
				[_client release];
				_client = nil;
			}
			if (_server) {
				[_server broadcastScreenConfiguration:nil];			
				if (_isRunning)
				[self stop:self];
				
				[_server release];
				_server = nil;
			}		
			
			[window setMinSize:NSMakeSize([window frame].size.width, kDefaultHeight)];
			if (_showAdvancedSettings) {
				[window setMaxSize:NSMakeSize([window frame].size.width, kMaxHeight)];
				frame.origin.y += frame.size.height - kDefaultHeight - kAdvandedSettingsHeight;
				frame.size.height = kDefaultHeight + kAdvandedSettingsHeight;
				[window setFrame:frame display:YES animate:YES];			
			}
			else {
				frame.origin.y += frame.size.height - kDefaultHeight;
				frame.size.height = kDefaultHeight;
				[window setMaxSize:NSMakeSize([window frame].size.width, kDefaultHeight)];
				[window setFrame:frame display:YES animate:YES];			
			}
			
			if (![_screens screensForKey:_hostName]) {
				[_screens setNSScreens:[NSScreen screens] forKey:_hostName];
				[_screens moveDownForKey:_hostName]; // HACK
				if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
				[qcView setValue:[_screens flatten] forInputKey:@"screens"];	
			}
		}
		else if (index == 1) {
			if (_client) {
				[_client release];
				_client = nil;
			}		
			_server = [Host new];
			
			[window setMinSize:NSMakeSize([window frame].size.width, kHostPaneHeight)];
			[window setMaxSize:NSMakeSize([window frame].size.width, kMaxHeight)];
			if (frame.size.height < kHostPaneHeight) {
				frame.origin.y += frame.size.height - kHostPaneHeight;
				frame.size.height = kHostPaneHeight;
				[window setFrame:frame display:YES animate:YES];
			}
			
			if (_doNotRunCompositionOnMaster) {
				[_screens removeScreensForKey:_hostName];
				[_server broadcastScreenConfiguration:_screens];
			}
		}	
		else if (index == 2) {
			if (_server) {
				[_server broadcastScreenConfiguration:nil];
				if (_isRunning)
				[self stop:self];

				[_server release];
				_server = nil;
			}
			_client = [Client new];
			[_screens setSavedScreens:nil];
			
			[window setMinSize:NSMakeSize([window frame].size.width, kClientPaneHeight)];
			[window setMaxSize:NSMakeSize([window frame].size.width, kMaxHeight)];
			if (frame.size.height > kClientPaneHeight) {
				frame.origin.y += frame.size.height - kClientPaneHeight;
				frame.size.height = kClientPaneHeight;
				[window setFrame:frame display:YES animate:YES];
			}
			if (![_screens screensForKey:_hostName]) {
				[_screens setNSScreens:[NSScreen screens] forKey:_hostName];
				[_screens moveDownForKey:_hostName]; // HACK
				if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
				[qcView setValue:[_screens flatten] forInputKey:@"screens"];	
			}
		}	
	}
}

- (void) setShowAdvancedSettings:(BOOL)show
{
	NSRect		frame = [window frame];
		
	_showAdvancedSettings = show;
	
	if (_showAdvancedSettings) {
		frame.origin.y -= kAdvandedSettingsHeight;
		frame.size.height += kAdvandedSettingsHeight;
		[window setMaxSize:NSMakeSize([window frame].size.width, kMaxHeight)];
		[settingsBox setHidden:NO];
	}
	else {
		frame.origin.y += frame.size.height - kDefaultHeight;
		frame.size.height = kDefaultHeight;
		[window setMaxSize:NSMakeSize([window frame].size.width, kDefaultHeight)];
		[settingsBox setHidden:YES];
	}
	
	[window setFrame:frame display:YES animate:YES];
}

- (void) setScreens:(Screens*)screens
{
	if (screens != _screens) {
		[_screens release];
		_screens = [screens retain];
		if (!_isRunning || (_doNotRunCompositionOnMaster && _server))
		[qcView setValue:[_screens flatten] forInputKey:@"screens"];
	}
}

- (void) setMasterCompositionCache:(NSDictionary*)param
{
	if (_masterCompositionCache != param) {
		[_masterCompositionCache release];
		_masterCompositionCache = [param retain];
	}
}

- (void) setResultsOnRenderer:(QCRenderer*)renderer
{
	NSArray*			rendererKeys = [renderer inputKeys];
	NSUInteger			i;
	NSString*			key;
	
	for (i=0; i<[rendererKeys count]; ++i) {
	    key = [rendererKeys objectAtIndex:i];
		if ([_masterCompositionCache objectForKey:key]) {
			if(![renderer setValue:[_masterCompositionCache valueForKey:key] forInputKey:key])
			NSLog(@"Could not set value for key: %@", key);
		}
	}
}

- (void) setVblSync:(BOOL)b
{
	if (b != _vblSync) {
		_vblSync = b;
		
		if (_server) {
			[self _broadcastAppParameters];
			
			if (_isRunning)
			[self _restart];
		}
	}
}

- (void) setMaxProcessingFramerate:(double)x
{
	if (x != _maxProcessingFramerate) {
		_maxProcessingFramerate = x;
		
		if (_server) {
			[self _broadcastAppParameters];
			
			if (_isRunning && _server)
			[self _restart];
		}
	}
}

- (void) setTimeSyncFramerate:(double)x
{
	if (x != _timeSyncFramerate) {
		_timeSyncFramerate = x;
		
		if (_server) {
			[self _broadcastAppParameters];
			
			if (_isRunning && _server)
			[self _restart];
		}
	}
}

- (void) setDistributeProcessingComposition:(BOOL)b
{
	if (b != _distributeProcessingComposition) {
		_distributeProcessingComposition = b;
		
		if (_server) {
			if (_processingCompositionData) {
				if (_distributeProcessingComposition)
				[_server broadcastProcessingComposition:_processingCompositionData];
				else
				[_server broadcastProcessingComposition:nil];
			}
			[self _broadcastAppParameters];
		
			if (_isRunning)
			[self _restart];
		}
	}
}

- (void) setDoNotRunCompositionOnMaster:(BOOL)b
{
	if (b != _doNotRunCompositionOnMaster) {
		_doNotRunCompositionOnMaster = b;
		
		if (_server) {
			if (_doNotRunCompositionOnMaster) 
			[_screens removeScreensForKey:_hostName];
			else {
				[_screens setNSScreens:[NSScreen screens] forKey:_hostName];
				[_screens moveDownForKey:_hostName];
			}
			if (!_isRunning || (_doNotRunCompositionOnMaster))
			[qcView setValue:[_screens flatten] forInputKey:@"screens"];	
			
			[_server broadcastScreenConfiguration:_screens];
			
			if (_isRunning)
			[self _restart];
		}
	}
}

- (void) setScreenBezel:(NSUInteger)bezel
{
	if (bezel != _screenBezel) {
		_screenBezel = bezel;
		
		if (_server) {
			[self _broadcastAppParameters];
			
			if (_isRunning && _server)
			[self _restart];
		}
	}
}

- (void) setUseBezel:(BOOL)useBezel
{
	if (useBezel != _useBezel) {
		_useBezel = useBezel;
		
		if (_server) {
			[self _broadcastAppParameters];
			
			if (_isRunning && _server)
			[self _restart];
		}
	}
}

- (BOOL)isRunning
{
	return _isRunning;
}

@end