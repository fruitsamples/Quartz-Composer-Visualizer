#import "Screens.h"

//FUNCTIONS:

static NSArray* _RectToArray(NSRect rect)
{
	return [NSArray arrayWithObjects:[NSNumber numberWithFloat:rect.origin.x], [NSNumber numberWithFloat:rect.origin.y],[NSNumber numberWithFloat:rect.size.width], [NSNumber numberWithFloat:rect.size.height], nil];
}

//CLASS INTERFACES:

@interface Screen(Private)
- (id) initWithNSScreen:(NSScreen*) screen offset:(NSPoint)offset;
- (void) setOrigin:(NSPoint)p;
@end

// A ScreenLits object representent all displays on one machine, and their location in the display array
@interface ScreenList : NSObject {
	NSArray*				_screenList;
	NSRect					_renderFrame;	// Render frame is smallest rect containing all screen rects
@public
	NSUInteger				_x, _y;
}

- (id) initWithScreens:(NSArray*)screens x:(NSUInteger)x y:(NSUInteger)y;
- (id) initWithNSScreens:(NSArray*)nsScreens;

- (NSRect) renderFrame;
- (NSArray*) screens;
- (void) setOriginX:(float)x;
- (void) setOriginY:(float)y;
@end

//CLASS IMPLEMENTATIONS:

@implementation Screen

- (id) initWithNSScreen:(NSScreen*) screen offset:(NSPoint)offset
{
	if ((self = [super init])) {
		_frame = [screen frame];
		_frame.origin.x += offset.x;
		_frame.origin.y += offset.y;		
		_displayID = [[[screen deviceDescription] valueForKey:@"NSScreenNumber"] integerValue];
	}

	return self;			
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeRect:_frame forKey:@"frame"];
	[aCoder encodeInt:_displayID forKey:@"displayID"];
	[aCoder encodeInt:_identifier forKey:@"identifier"];
}

- (id) initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super init])) {
		_frame = [aDecoder decodeRectForKey:@"frame"];
		_displayID = [aDecoder decodeIntForKey:@"displayID"];
		_identifier = [aDecoder decodeIntForKey:@"identifier"];
	}

	return self;
}

- (CGDirectDisplayID) displayID
{
	return _displayID;
}

- (NSRect) frame
{
	return _frame;
}

- (void) translateOrigin:(NSPoint)p
{
	_frame.origin.x += p.x;
	_frame.origin.y += p.y;
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"(DisplayID: %i, frame: (%f, %f, %f, %f))", _displayID, _frame.origin.x, _frame.origin.y, _frame.size.width, _frame.size.height];
}

- (NSComparisonResult) _compare:(Screen*)screen
{
	return (_frame.origin.x <= [screen frame].origin.x) && (_frame.origin.y <= [screen frame].origin.y) ? NSOrderedAscending : NSOrderedDescending;
}

- (void) _translateOriginOfOrigin:(NSValue*)pointValue
{
	NSPoint*			point = [pointValue pointerValue];
	
	[self translateOrigin:NSMakePoint(-point->x, -point->y)];
}

@end

@implementation ScreenList

- (id) initWithNSScreens:(NSArray*)nsScreens
{
	NSUInteger		i;
	NSRect			frame;
	NSScreen*		nsScreen;
	Screen*			screen;
	double			minX = 10000., minY = 10000.;
	
	if ((self = [super init])) {
		_renderFrame = NSZeroRect;
		_screenList = [NSMutableArray new];

		for (i=0; i<[nsScreens count]; ++i) {
			nsScreen = [nsScreens objectAtIndex:i];
			minX = MIN(minX, [nsScreen frame].origin.x);
			minY = MIN(minY, [nsScreen frame].origin.y);			
		}
		
		for (i=0; i<[nsScreens count]; ++i) {
			nsScreen = [nsScreens objectAtIndex:i];
			screen = [[Screen alloc] initWithNSScreen:nsScreen offset:NSMakePoint(-minX, minY)];
			frame = [screen frame];	
			[(NSMutableArray*)_screenList addObject:screen];
			[screen release];

			// Update render frame
			_renderFrame.origin.x = MIN(_renderFrame.origin.x, frame.origin.x);
			_renderFrame.origin.y = MIN(_renderFrame.origin.y, frame.origin.y);
			_renderFrame.size.width = MAX(_renderFrame.size.width, frame.origin.x + frame.size.width);
			_renderFrame.size.height = MAX(_renderFrame.size.height, frame.origin.y + frame.size.height);			
		}
	}

	return self;
}

- (id) initWithScreens:(NSArray*)screens x:(NSUInteger)x y:(NSUInteger)y
{
	NSUInteger		i;
	NSRect			frame;
	
	if ((self = [super init])) {
		_renderFrame = NSZeroRect;
		_screenList = [screens retain];
		_x = x;
		_y = y;		
		
		// Update render frame
		for (i=0; i<[screens count]; ++i) {
			frame = [(Screen*)[screens objectAtIndex:i] frame];
			_renderFrame.origin.x = MIN(_renderFrame.origin.x, frame.origin.x);
			_renderFrame.origin.y = MIN(_renderFrame.origin.x, frame.origin.x);
			_renderFrame.size.width = MAX(_renderFrame.size.width, frame.origin.x + frame.size.width);
			_renderFrame.size.height = MAX(_renderFrame.size.height, frame.origin.y + frame.size.height);			
		}
	}

	return self;
}

- (void) dealloc
{
	[_screenList release];
	
	[super dealloc];
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeInt:_x forKey:@"x"];
	[aCoder encodeInt:_y forKey:@"y"];
	[aCoder encodeObject:_screenList forKey:@"screenList"];	
	[aCoder encodeRect:_renderFrame forKey:@"renderFrameList"];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super init])) {
		_x = [aDecoder decodeIntForKey:@"x"];
		_y = [aDecoder decodeIntForKey:@"y"];
		_screenList = [[aDecoder decodeObjectForKey:@"screenList"] retain];
		_renderFrame = [aDecoder decodeRectForKey:@"renderFrameList"];
	}

	return self;
}

- (NSRect) renderFrame
{
	return _renderFrame;
}

- (NSArray*) screens
{
	return _screenList;
}

- (void) setOriginX:(float)x
{
	NSUInteger			i;
	
	for (i=0; i<[_screenList count]; ++i)
	[[_screenList objectAtIndex:i] translateOrigin:NSMakePoint(x-_renderFrame.origin.x, 0.)];
	
	_renderFrame.origin.x = x;
}

- (void) setOriginY:(float)y
{
	NSUInteger			i;
	
	for (i=0; i<[_screenList count]; ++i)
	[[_screenList objectAtIndex:i] translateOrigin:NSMakePoint(0., y-_renderFrame.origin.y)];

	_renderFrame.origin.y = y;
}

- (NSUInteger) x
{
	return _y;
}

- (NSUInteger) y
{
	return _y;
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"(%i, %i: %@)", _x, _y, _screenList];
}

@end

@implementation Screens

- (id) init
{
	if ((self = [super init])) {
		_screens = [NSMutableDictionary new];
		_renderFrame = NSZeroRect;
	}
	
	return self;
}

- (void) setSavedScreens:(Screens*)screens
{
	if (screens != _savedScreens) {
		[_savedScreens release];
		_savedScreens = [screens retain];
	}
}

- (void) dealloc
{
	if (_savedScreens)
	[_savedScreens release];
	[_screens release];
	
	[super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeRect:_renderFrame forKey:@"renderFrame"];
	[aCoder encodeObject:_screens forKey:@"screens"];	
	[aCoder encodeInt:_hCount forKey:@"hCount"];	
	[aCoder encodeInt:_vCount forKey:@"vCount"];		
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super init])) {
		_renderFrame = [aDecoder decodeRectForKey:@"renderFrame"];
		_screens = [[aDecoder decodeObjectForKey:@"screens"] retain];
		_hCount = [aDecoder decodeIntForKey:@"hCount"];
		_vCount = [aDecoder decodeIntForKey:@"vCount"];
	}

	return self;
}

- (ScreenList*) _screenListForX:(NSUInteger)x y:(NSUInteger)y
{
	NSEnumerator*	enumerator = [_screens objectEnumerator];
	ScreenList*		screenList, *result = nil;
	
	
	while ((screenList = [enumerator nextObject])) {		// Since there won't be a big number of screens in general, we can afford this non-efficient search
		if ((screenList->_x == x) && (screenList->_y == y)) {
			result = screenList;
			break;
		}
	}
	
	return screenList;
}

- (void) _updateRenderFrame
{
	ScreenList*		screenList;
	NSUInteger		i, j;
	float			width, max, maxHeight = 0., maxWidth = 0., maxWidthColumn[_vCount];
	NSEnumerator*	objectEnumerator = [_screens objectEnumerator];

	_hCount = 0;
	_vCount = 0;	
	while ((screenList = [objectEnumerator nextObject])) {
		_hCount = MAX(_hCount, screenList->_x + 1);
		_vCount = MAX(_vCount, screenList->_y + 1);
	}
	
	for (i=0; i<_hCount; ++i) {
		maxWidthColumn[i] = 0.;
		for (j=0; j<_vCount; ++j) {
			if ((screenList = [self _screenListForX:i y:j]))
			maxWidthColumn[i] = MAX(maxWidthColumn[i], [screenList renderFrame].size.width);
		}
		maxWidth = maxWidth + maxWidthColumn[i];
	}
	
	for (j=0; j<_vCount; ++j) {
		width = 0.;
		max = 0.;
		for (i=0; i<_hCount; ++i) {
			if ((screenList = [self _screenListForX:i y:j])) {
				[screenList setOriginX:width];
				[screenList setOriginY:maxHeight];
				max = MAX(max, [screenList renderFrame].size.height);
			}
			width += maxWidthColumn[i];
 		}
		maxHeight += max;
	}

	// Update render frame
	_renderFrame.origin.x = 0.;
	_renderFrame.origin.y = 0.;
	_renderFrame.size.width = maxWidth;
	_renderFrame.size.height = maxHeight;			
}

// This function is called not to leave holes between screen indexes
- (void) _consolidate
{
	NSUInteger		i, j, k;
	ScreenList*		screenList;
		
	[_savedScreens release];
	_savedScreens = nil;
	
	// Horizontal pass
	for (j=0; j<_vCount; ++j) {
		for (i=1; i<_hCount; ++i) {
			if ((screenList = [self _screenListForX:i y:j])) {
				k = 1;
				while (![self _screenListForX:i-k y:j] && (k<=i)) {
					screenList->_x = i-k;
					k++;
				}
			}
		}
	}
	
	// Vertical pass
	for (i=0; i<_hCount; ++i) {
		for (j=0; j<_vCount; ++j) {
			if ((screenList = [self _screenListForX:i y:j])) {
				k = 1;
				while (![self _screenListForX:i y:j-k] && (k<=j)) {
					screenList->_y = j-k;
					k++;
				}
			}
		}
	}
	
	_consolidated = YES;
	
	[self _updateRenderFrame];
}

- (NSArray*) screensForKey:(NSString*)name
{
	return [(ScreenList*)[_screens valueForKey:name] screens];
}

- (ScreenList*) _copySavedScreensForScreens:(NSArray*)screens key:(NSString*)name
{
	ScreenList*			screenList = nil, *savedList;
	NSArray*			savedArray;
	BOOL				foundSaved = NO;
	NSUInteger			x;
	
	// Look in saved database for screens from same machine
	if (_savedScreens && (savedArray = [_savedScreens screensForKey:name]) && ([savedArray  count] == [screens count])) {
		foundSaved = YES;
		for (x=0; x<[savedArray count]; ++x) {
			if (!NSEqualSizes([(Screen*)[savedArray objectAtIndex:x] frame].size, [(Screen*)[screens objectAtIndex:x] frame].size)) {
				foundSaved = NO;
				break;
			}
		}
		if (foundSaved) {
			savedList = [(NSDictionary*)[_savedScreens valueForKey:@"screens"] valueForKey:name];
			screenList = [[ScreenList alloc] initWithScreens:screens x:savedList->_x y:savedList->_y];
		}
	}
	
	return screenList;
}

- (void) setScreens:(NSArray*)screens forKey:(NSString*)name
{
	ScreenList*			screenList;
	NSUInteger			y = 0;
	NSEnumerator*		enumerator = [_screens objectEnumerator];

	if (!(screenList = [self _copySavedScreensForScreens:screens key:name])) { // If could not find, put on top of others
		while ((screenList = [enumerator nextObject]))
		y = MAX(y, screenList->_y);
		
		screenList = [[ScreenList alloc] initWithScreens:screens x:0 y:y+1]; 
	}
	if (screenList) {
		[_screens setValue:screenList forKey:name];
		[screenList release];

		// Update render frame
		[self _updateRenderFrame];
	}
	else
	NSLog (@"ERROR: Could not create ScreenList");
}

- (void) setNSScreens:(NSArray*)nsScreens forKey:(NSString*)name
{
	ScreenList*			screenList = [[ScreenList alloc] initWithNSScreens:nsScreens],
						*savedList, *list;
	NSEnumerator*		enumerator;
	
	savedList = [self _copySavedScreensForScreens:[screenList screens] key:name];
	if (savedList) {
		[screenList release];
		[_screens setValue:savedList forKey:name];
		[savedList release];

		// Update render frame
		[self _updateRenderFrame];
	}
	else if (screenList) {
		enumerator = [_screens objectEnumerator];
		while ((list = [enumerator nextObject]))
		list->_y++;

		[_screens setValue:screenList forKey:name];
		[screenList release];
		
		// Update render frame
		[self _updateRenderFrame];
	}
	else
	NSLog (@"ERROR: Could not create ScreenList");
}

- (void) removeScreensForKey:(NSString*)name
{
	[_screens removeObjectForKey:name];

	[self _updateRenderFrame];
}

- (void) removeAllScreens
{
	[_screens removeAllObjects];
}

- (NSArray*) flatten
{
	NSEnumerator*							enumerator = [_screens keyEnumerator];
	NSString*								key;
	NSMutableArray*							result = [NSMutableArray new];
	NSArray*								array;
	NSUInteger								i;
	
	while ((key = [enumerator nextObject])) {
		array = [(ScreenList*)[_screens valueForKey:key] screens];
		for (i=0; i<[array count]; ++i)
		[result addObject:[NSArray arrayWithObjects:key, _RectToArray([(Screen*)[array objectAtIndex:i] frame]), nil]];
	}
	
	return [result autorelease];
}

- (NSRect) renderFrame
{
	return _renderFrame;
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"(%@, \nrenderFrame: (%f, %f, %f, %f))", [_screens description], _renderFrame.origin.x, _renderFrame.origin.y, _renderFrame.size.width, _renderFrame.size.height];
}

- (void) moveLeftForKey:(NSString*)key
{
	ScreenList*		src, *dst;
	NSUInteger		i;
	
	if (!_consolidated)
	[self _consolidate];
	
	if ((src = [_screens valueForKey:key])) {
		if (src->_x == 0)
		return;

		if ((dst = [self _screenListForX:src->_x-1 y:src->_y])) {
			i = src->_x;
			dst->_x = i;
			src->_x = i-1;
		}
		else if ([self _screenListForX:src->_x y:src->_y-1] || [self _screenListForX:src->_x y:src->_y+1] || [self _screenListForX:src->_x-1 y:src->_y+1] || [self _screenListForX:src->_x-1 y:src->_y-1])
		src->_x--;
		else
		return;

		[self _updateRenderFrame];
	}
}

- (void) moveRightForKey:(NSString*)key
{
	ScreenList*		src, *dst;
	NSUInteger		i;
	
	if (!_consolidated)
	[self _consolidate];

	if ((src = [_screens valueForKey:key])) {
		if ((dst = [self _screenListForX:src->_x+1 y:src->_y])) {
			i = src->_x;
			dst->_x = i;
			src->_x = i+1;
		}
		else if ([self _screenListForX:src->_x y:src->_y-1] || [self _screenListForX:src->_x y:src->_y+1] || [self _screenListForX:src->_x+1 y:src->_y+1] || [self _screenListForX:src->_x+1 y:src->_y-1])
		src->_x++;
		else
		return;
		
		[self _updateRenderFrame];
	}
}

- (void) moveUpForKey:(NSString*)key
{
	ScreenList*		src, *dst;
	NSUInteger		i;

	if (!_consolidated)
	[self _consolidate];
	
	if ((src = [_screens valueForKey:key])) {
		if ((dst = [self _screenListForX:src->_x y:src->_y+1])) {
			i = src->_y;
			dst->_y = i;
			src->_y = i+1;
		}
		else if ([self _screenListForX:src->_x-1 y:src->_y] || [self _screenListForX:src->_x+1 y:src->_y] || [self _screenListForX:src->_x-1 y:src->_y+1] || [self _screenListForX:src->_x+1 y:src->_y+1])
		src->_y++;
		else
		return;

		[self _updateRenderFrame];
	}
}

- (void) moveDownForKey:(NSString*)key
{
	ScreenList*		src, *dst;
	NSUInteger		i;
		
	if (!_consolidated)
	[self _consolidate];

	if ((src = [_screens valueForKey:key])) {
		if (src->_y == 0)
		return;
		
		if ((dst = [self _screenListForX:src->_x y:src->_y-1])) {
			i = src->_y;
			dst->_y = i;
			src->_y = i-1;
		}
		else if ([self _screenListForX:src->_x-1 y:src->_y] || [self _screenListForX:src->_x y:src->_y] || [self _screenListForX:src->_x-1 y:src->_y-1] || [self _screenListForX:src->_x+1 y:src->_y+1])
		src->_y--;
		else
		return;

		[self _updateRenderFrame];
	}
}

@end
