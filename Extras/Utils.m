#import "Utils.h"

// FUNCTIONS:

NSString* _ValidateServiceType(NSString* type)
{
	if([type length]) {
		if(![type hasPrefix:@"_"])
		type = [@"_" stringByAppendingString:type];
		if(![type hasSuffix:@"._tcp."])
		type = [type stringByAppendingString:@"._tcp."];
	}
	else
	type = nil;
	
	return type;
}

NSArray* _RectToArray(NSRect rect)
{
	return [NSArray arrayWithObjects:	[NSNumber numberWithFloat:rect.origin.x],
										[NSNumber numberWithFloat:rect.origin.y],
										[NSNumber numberWithFloat:rect.size.width],
										[NSNumber numberWithFloat:rect.size.height], nil];
}
