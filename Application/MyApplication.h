#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

#import "ProcessingRenderer.h"
#import "DrawingRenderer.h"
#import "Host.h"
#import "Client.h"
#import "Screens.h"

@class IconView;

@interface MyApplication : NSApplication
{
	IBOutlet NSWindow*				window;
	IBOutlet QCView*				qcView;
	IBOutlet IconView*				drawingCompositionIconView;
	IBOutlet IconView*				processingCompositionIconView;
	IBOutlet IconView*				drawingCompositionIconViewHost;
	IBOutlet IconView*				processingCompositionIconViewHost;
	IBOutlet NSTableView*			tableView;
	IBOutlet NSBox*					settingsBox;
	
	ProcessingRenderer*				_processorRenderer;
	NSMutableArray*					_drawingRenderers;
	
	BOOL							_decoupledCompositions,
									_isRunning,
									_vblSync,
									_useNetwork,
									_distributeProcessingComposition,
									_showAdvancedSettings,
									_doNotRunCompositionOnMaster,
									_useBezel;
	double							_maxProcessingFramerate,
									_timeSyncFramerate;
	NSString*						_processingCompositionPath,
									*_drawingCompositionPath;
	QCComposition*					_processingComposition,
									*_drawingComposition;
	NSData*							_processingCompositionData,
									*_drawingCompositionData;
	Screens*						_screens;
	NSString*						_hostName;
	NSInteger						_selectedRow;
	NSUInteger						_screenBezel;
									
	Host*							_server;
	Client*							_client;
	NSUInteger						_hostType;
	NSTimer*						_hostTimer;
	NSTimeInterval					_hostStartTime;
	NSDictionary*					_masterCompositionCache;
	CFRunLoopTimerRef				_activityTimer;
}

/* -- COMMON METHODS -- */

/* Actions called from the user interface */
- (IBAction) loadDrawingComposition:(id)sender;
- (IBAction) loadProcessingComposition:(id)sender;
- (IBAction) play:(id)sender;
- (IBAction) stop:(id)sender;

/* For IconView */
- (void) setCompositionPath:(NSString*)path iconView:(IconView*)sender;

/* -- NETWORK METHODS -- */

/* Changing screen locations */
- (IBAction) moveLeft:(id)sender;
- (IBAction) moveRight:(id)sender;
- (IBAction) moveUp:(id)sender;
- (IBAction) moveDown:(id)sender;

/* Changing client state */
- (IBAction) setSelected:(id)sender;
- (IBAction) setActive:(id)sender;

/* Managing clients */
- (void) addClient:(NSString*)name screens:(NSArray*)screens;
- (void) removeClient:(NSString*)name;

/* Reset screen location to default location */
- (void) resetScreens;

/* For time synchronization */
- (void) setTime:(NSTimeInterval) time;

@end