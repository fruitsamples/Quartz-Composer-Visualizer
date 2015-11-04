#import "IconView.h"
#import "MyApplication.h"

@implementation IconView

- (NSDragOperation) draggingEntered:(id<NSDraggingInfo>)sender
{
	NSPasteboard*			pboard = [sender draggingPasteboard];
	NSArray*				files;
	
	if([self isEnabled] && [pboard availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]]) {
		files = [pboard propertyListForType:NSFilenamesPboardType];
		if([files count] == 1) {
			if([[[files objectAtIndex:0] pathExtension] isEqualToString:@"qtz"])
			return NSDragOperationCopy;
		}
	}
	
	return NSDragOperationNone;
}

- (void) draggingExited:(id<NSDraggingInfo>)sender
{
	//Do nothing
}

- (BOOL) prepareForDragOperation:(id<NSDraggingInfo>)sender
{
	//Do nothing
	return YES;
}

- (BOOL) performDragOperation:(id<NSDraggingInfo>)sender
{
	NSPasteboard*			pboard = [sender draggingPasteboard];
	NSString*				path;
	
	if([pboard availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]]) {
		path = [[pboard propertyListForType:NSFilenamesPboardType] objectAtIndex:0];
		[(MyApplication*)NSApp setCompositionPath:path iconView:self];
		return YES;
	}
	
	return NO;
}

- (void) concludeDragOperation:(id<NSDraggingInfo>)sender
{
	//Do nothing
}

- (void) setImage:(NSImage*)image
{
	if (image == nil) 
	[(MyApplication*)NSApp setCompositionPath:nil iconView:self];
	
	[super setImage:image];
}

@end
