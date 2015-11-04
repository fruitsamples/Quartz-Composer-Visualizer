#import <Cocoa/Cocoa.h>
#import <pthread.h>

#import "Host.h"

@interface ProcessingRenderer : NSObject
{
@private
	pthread_mutex_t			_executionMutex,
							_eventMutex,
							_resultParametersMutex;
	NSMutableDictionary*	_resultParameters;
	NSMutableArray*			_eventQueue;
	NSTimeInterval			_startTime;
	BOOL					_isRunning;
	NSTimer*				_timer;
	QCRenderer*				_renderer;
}

/* Initialiazing ProcessingRenderer: it will run in a separate thread */
- (id) initWithComposition:(QCComposition*)composition framerate:(double)fps;

/* Stopping ProcessingRenderer, and terminating associated thread */
- (void) stop;

/* Queuing a keyboard or mouse event */
- (void) queueEvent:(NSEvent *)event mouseLocation:(NSPoint)mouseLocation;

/* Called by DrawingRenderer to set the ProcessingRenderer results on itself */
- (void) setResultsOnRenderer:(QCRenderer*)renderer;

/* If ProcessingRenderer runs on host, this method is used to forward the composition outputPorts values to all clients inputPorts */
- (void) broadcastResultsUsingHost:(Host*)host;

/* For time synchronization */
- (void) setTime:(NSTimeInterval) time;
@end
