#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <pthread.h>

#import "ProcessingRenderer.h"
#import "Screens.h"

#define kDrawingRendererOptionsKey_ShareContext		@"shareContext"
#define kDrawingRendererOptionsKey_VBLSyncing		@"vblSyncing"
#define kDrawingRendererOptionsKey_ScreenBezel		@"screenBezel"

@interface DrawingRenderer : QCRenderer 
{
@private
	ProcessingRenderer*		_processorRenderer;
	NSOpenGLContext*		_glContext;
	CVDisplayLinkRef		_displayLink;
	NSRect					_subRegion,
							_screenFrame;
	NSTimeInterval			_startTime;
	CGDirectDisplayID		_displayID;
	GLint					_rendererID;
	NSWindow*				_window;
	NSTimer*				_timer;
	NSMutableArray*			_eventQueue;
	pthread_mutex_t			_eventMutex;
}

/* Returns the rendererID of the card on which the visualizer is running on, used for sharing contexts of DrawingRenderer running on the same card */
+ (GLint) rendererIDForDisplayID:(CGDirectDisplayID)displayID;

/* Initializing composition which will run in separate thread with a CVDisplayLink attached to full screen openGL context */
- (id) initWithComposition:(QCComposition*)composition screen:(Screen*)screen renderFrame:(NSRect)renderFrame withProcessingRenderer:(ProcessingRenderer*)processor options:(NSDictionary*)options;

/* Queuing a keyboard or mouse event */
- (void) queueEvent:(NSEvent*)event;

/* Accessing info of DrawingRenderer */
- (NSOpenGLContext*) openGLContext;
- (GLint) rendererID;

/* For time synchronization */
- (void) setTime:(NSTimeInterval)time;
@end

