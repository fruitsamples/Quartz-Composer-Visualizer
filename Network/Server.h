#import "Service.h"
#import "Connection.h"

//CLASS INTERFACES:

@interface Server : Service
{
@private
	pthread_mutex_t		_connectionsMutex;
	NSMutableArray*		_connections;
	id					_delegate; //Not retained
}
- (NSArray*) connections;
- (id) delegate;
- (void) setDelegate:(id)delegate;
@end

@interface ServerConnection : Connection
{
@private
	Server*			_server; //Not retained
}
- (Server*) server;
@end

@interface NSObject (ServerDelegate)
- (void) serverDidStart:(Server*)server;
- (void) serverWillStop:(Server*)server;
@end
