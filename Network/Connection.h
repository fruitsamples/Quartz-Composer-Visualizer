#import <Foundation/Foundation.h>

//CLASS INTERFACES:

@interface Connection : NSObject
{
@private
	CFReadStreamRef		_inputStream;
	CFWriteStreamRef	_outputStream;
	CFRunLoopRef		_runLoop;
	id					_delegate;
	BOOL				_opened,
						_active;
	NSString*			_address;
	NSString*			_name;
	
	NSMutableData*		_inputData;
	NSUInteger			_inputCapacity;
	NSMutableArray*		_inputMessages;
	BOOL				_inputPending;
	
	NSData*				_outputData;
	NSUInteger			_outputCapacity;
	NSMutableArray*		_outputMessages;
	BOOL				_outputPending;
}
- (id) initWithSocketHandle:(NSSocketNativeHandle)socket;
- (id) initWithServiceDomain:(NSString*)domain type:(NSString*)type name:(NSString*)name timeOut:(NSTimeInterval)timeOut;
- (id) initWithCFNetService:(CFNetServiceRef)service timeOut:(NSTimeInterval)timeOut;
- (id) initWithNetService:(NSNetService*)service;

- (void) setDelegate:(id)delegate;
- (id) delegate;

- (BOOL) isOpened;
- (NSString*) remoteAddress; //Valid only after connection is opened
- (NSString*) remoteHostName; //Valid only after connection is opened

- (BOOL) isValid;
- (void) invalidate;
- (BOOL) active;
- (void) setActive:(BOOL)active;

- (BOOL) sendData:(NSData*)data timeOut:(NSTimeInterval)limit; //Doesn't block if timeout is zero
- (NSData*) receiveDataWithTimeOut:(NSTimeInterval)limit; //Doesn't block if timeOut is zero
- (NSData*) sendDataAndWaitForResponse:(NSData*)data timeOut:(NSTimeInterval)limit;//Fails if timeOut is zero
- (BOOL) hasDataAvailable;
@end

@interface NSObject (ConnectionDelegate)
- (void) connectionDidOpen:(Connection*)connection;
- (void) connectionDidInvalidate:(Connection*)connection;
- (void) connectionDidReceiveMessage:(Connection*)connection;
@end
