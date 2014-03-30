//
//  CCHMapClusterOperation.h
//  CCHMapClusterController
//
//  Copyright (C) 2014 Claus Höfele
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

@class CCHMapClusterController;
@class CCHMapClusterAnnotation;
@class CCHMapTree;
@protocol CCHMapClusterer;
@protocol CCHMapAnimator;
@protocol CCHMapClusterControllerDelegate;

@interface CCHMapClusterOperation : NSOperation

@property (nonatomic, copy) CCHMapClusterAnnotation *(^findVisibleAnnotation)(NSSet *annotations, NSSet *visibleAnnotations);
@property (nonatomic, copy) void (^completionHandler)();

@property (nonatomic, strong) CCHMapTree *allAnnotationsMapTree;
@property (nonatomic, strong) CCHMapTree *visibleAnnotationsMapTree;
@property (nonatomic, strong) id<CCHMapClusterer> clusterer;
@property (nonatomic, strong) id<CCHMapAnimator> animator;
@property (nonatomic, weak) id<CCHMapClusterControllerDelegate> delegate;
@property (nonatomic, weak) CCHMapClusterController *clusterController;

- (id)initWithMapView:(MKMapView *)mapView cellSize:(double)cellSize marginFactor:(double)marginFactor;

+ (double)cellMapSizeForCellSize:(double)cellSize withMapView:(MKMapView *)mapView;
+ (MKMapRect)gridMapRectForMapRect:(MKMapRect)mapRect withCellMapSize:(double)cellMapSize marginFactor:(double)marginFactor;

@end
