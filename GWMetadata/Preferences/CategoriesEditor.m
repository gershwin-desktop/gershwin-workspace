/* CategoriesEditor.m
 *  
 * Copyright (C) 2006 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: December 2006
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#include <AppKit/AppKit.h>
#include "CategoriesEditor.h"
#include "CategoryView.h"
#include "MDIndexing.h"

#define LINEH (28.0)

@implementation CategoriesEditor

- (void)dealloc
{
  RELEASE (categories);
  RELEASE (catviews);

  [super dealloc];
}

- (id)initWithFrame:(NSRect)rect
{
  self = [super initWithFrame: rect];
  
  if (self) {
    catviews = [NSMutableArray new];
    [self showSavedCategories];
  }

  return self;
}

- (void)setMdindexing:(id)anobject
{
  mdindexing = anobject;
  [mdindexing searchResultDidEndEditing];
}

- (void)categoryViewDidChangeState:(CategoryView *)view
{
  [mdindexing searchResultDidStartEditing];
}

- (void)moveCategoryViewAtIndex:(int)srcind
                        toIndex:(int)dstind
{
  CategoryView *view = [catviews objectAtIndex: srcind];
  id dummy = [NSString string];
  int i;
  
  RETAIN (view);  
  [catviews replaceObjectAtIndex: srcind withObject: dummy];  
  [catviews insertObject: view atIndex: dstind];
  [catviews removeObject: dummy];
  RELEASE (view);  

  for (i = 0; i < [catviews count]; i++) {
    [[catviews objectAtIndex: i] setIndex: i];
  }   
  
  [self tile];
  [self setNeedsDisplay: YES];    
  [mdindexing searchResultDidStartEditing];
}

- (void)applyChanges
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
  NSMutableDictionary *newcat = [NSMutableDictionary dictionary];
  NSMutableDictionary *domain;    
  int i;
  
  for (i = 0; i < [catviews count]; i++) { 
    NSDictionary *catinfo = [[catviews objectAtIndex: i] categoryInfo];
    NSString *catname = [catinfo objectForKey: @"category_name"];
    
    [newcat setObject: catinfo forKey: catname];
  }   
  
  [defaults synchronize];
  domain = [[defaults persistentDomainForName: @"MDKQuery"] mutableCopy];
  /* Showing the categories no longer seeds the domain, so saving can come
     before MDKQuery has created it. */
  if (domain == nil) {
    domain = [NSMutableDictionary new];
  }
  [domain setObject: newcat forKey: @"categories"];
  [defaults setPersistentDomain: domain forName: @"MDKQuery"];
  RELEASE (domain);  
  [defaults synchronize];  

  [[NSDistributedNotificationCenter defaultCenter]
           postNotificationName: @"MDKQueryCategoriesDidChange"
	 								       object: nil 
                       userInfo: nil];
  
  [mdindexing searchResultDidEndEditing];
}

- (void)revertChanges
{
  [self showSavedCategories];
  [self tile];
  [mdindexing searchResultDidEndEditing];
}

/* Only reads: this view is built with the pane's main view, which a host
   may load just to index its labels, and MDKQuery seeds the domain itself
   when it first runs. */
- (NSDictionary *)savedCategories
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *catdict;

  [defaults synchronize];
  catdict = [[defaults persistentDomainForName: @"MDKQuery"] objectForKey: @"categories"];

  if ([catdict count] == 0) {
    NSBundle *bundle = [NSBundle bundleForClass: [self class]];
    NSString *dictpath = [bundle pathForResource: @"categories" ofType: @"plist"];

    catdict = [NSDictionary dictionaryWithContentsOfFile: dictpath];

    if (catdict == nil) {
      [NSException raise: NSInternalInconsistencyException
                  format: @"\"%@\" doesn't contain a dictionary!", dictpath];
    }
  }

  return catdict;
}

- (void)showSavedCategories
{
  NSArray *catnames;
  unsigned i;

  DESTROY (categories);
  categories = [[self savedCategories] mutableCopy];
  catnames = [categories keysSortedByValueUsingSelector: @selector(compareAccordingToIndex:)]; 

  while ([catviews count]) { 
    CategoryView *cview = [catviews objectAtIndex: 0];
    
    [cview removeFromSuperview];
    [catviews removeObject: cview];
  }
    
  for (i = 0; i < [catnames count]; i++) { 
    NSString *catname = [catnames objectAtIndex: i];   
    NSDictionary *catinfo = [categories objectForKey: catname];
    CategoryView *cview = [[CategoryView alloc] initWithCategoryInfo: catinfo
                                                            inEditor: self];
    [catviews addObject: cview];
    [self addSubview: cview];
    RELEASE (cview);      
  }
}

- (void)tile
{
  NSView *sview = [self superview];
  float sh = (sview != nil) ? [sview bounds].size.height : 0.0;
  NSRect rect = [self frame];
  int count = [catviews count];
  float vspace = count * LINEH;
  int i;
    
  rect.size.height = (vspace > sh) ? vspace : sh;
  vspace = rect.size.height;
  [self setFrame: rect];
  
  for (i = 0; i < count; i++) {     
    vspace -= LINEH;
    [[catviews objectAtIndex: i] setFrameOrigin: NSMakePoint(0, vspace)];
  }
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];
  [self tile];
}

@end


@implementation NSDictionary (CategorySort)

- (NSComparisonResult)compareAccordingToIndex:(NSDictionary *)dict
{
  NSNumber *p1 = [self objectForKey: @"index"];
  NSNumber *p2 = [dict objectForKey: @"index"];
  return [p1 compare: p2];
}

@end

