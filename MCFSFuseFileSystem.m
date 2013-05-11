#import "MCFSFuseFileSystem.h"
#import <OSXFUSE/OSXFUSE.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void directory();

NSMutableDictionary *cachedDirectoryContents = nil;

int max_sector = 0;

typedef struct
{
	union
	{
		unsigned char	data[128];
		unsigned short	words[64];
		unsigned short	pointer;
	};
} sector_struct;

sector_struct sector[2048];

int is_mcfs()
{
	return (strncmp(&sector[0].data[0x7c],"MCFS",4) == 0);
}

int is_allocated(int s)
{
	s &= 0x7ff;
	
	return ( sector[4+(s >> 10)].data[(s >> 3) & 0x7f] >> (7 - (s & 7)) ) & 1;
}

void allocate(int s)
{
	s &= 0x7ff;
	sector[4+(s >> 10)].data[(s >> 3) & 0x7f] |= 1 << (7 - (s & 7));
}

void deallocate(int s)
{
	s &= 0x7ff;
	sector[4+(s >> 10)].data[(s >> 3) & 0x7f] &= !(1 << (7 - (s & 7)));
}

int findfirstfree()
{
	int s = 0;
	while ( (s<2048) && is_allocated(s) ) s++;
	
	return s;
}

int findfreedirentry()
{
	int i=1;
	
	while (i<40)
	{
		if (sector[6+(i>>2)].words[(i&3)<<4] == 0)
			return i;
		i++;
	}
	
	return 0;
	
}

int findname(char *name)
{
	unsigned char n[32];
	int i;
	
	
	if (*name == 0)
		return -1;
	
	i = 0;
	memset(&n, 0x00, sizeof(n));
	
	while ((i<28) && *name)
	{
		if ((*name>=0x20) && (*name<0x7f))
			n[i++] = *name;
		else
			n[i++] = 0x20;
		
		*name ++;
	}
	
	n[i-1] |= 0x80;
	
	i=1;
	while (i<40)
	{
		if (sector[6+(i>>2)].words[(i&3)<<4])
		{
			if (memcmp(&sector[6+(i>>2)].data[((i&3)<<5) + 4], &n, 28) == 0)
			{
				return i;
			}
		}
		i ++;
	}
	return 0;
}


void dumpsam()
{
	int i,j;
	
	for (i=0; i<31; i++)
	{
		printf(" %4d  ",i*64);
		for (j=0; j<63; j++)
		{
			if (!(j%8))
				putchar(' ');
			putchar('-' - 2*is_allocated(i*64+j));
		}
		putchar('\n');
	}
}

int writefile(char *name)
{
	FILE *f;
	int s, ns, ss, size, i, j, idx;
	int count = 0;
	
	if (findname(name)!=0)
	{
		printf("File exists %s\n",name);
		return -1;
	}
	
	idx = findfreedirentry();
	if (!idx)
	{
		printf("directory full\n");
		return -1;
	}
	
	if ( (f = fopen(name,"rb")) == NULL)
	{
		printf("err: fopen [%s]\n",name);
		return -1;
	}
	
	fseek(f,0,SEEK_END);
	size=ftell(f);
	fseek(f,0,SEEK_SET);
	
	if (size>0)
	{
		i = 0;
		while ((i<28) && *name)
		{
			if ((*name>=0x20) && (*name<0x7f))
				sector[6+(idx>>2)].data[((idx&3)<<5) + 4 + i++] = *name;
			else
				sector[6+(idx>>2)].data[((idx&3)<<5) + 4 + i++] = 0x20;
			
			*name ++;
		}
		
		if (i>0)
			sector[6+(idx>>2)].data[((idx&3)<<5) + 3 + i] |= 0x80;
		
		ns = findfirstfree();
		ss = ns;
		while (size>0)
		{
			s = ns;
			
			allocate(s);
			memset(&sector[s],0x00,0x80);
			count ++;
			
			if (max_sector< (s+1))
				max_sector = (s+1);
			
			ns = findfirstfree();
			
			if (size>0x7e)
			{
				sector[s].pointer = ns;
				size -= 0x7e;
				fread(&sector[s].data[2], 1, 0x7e, f);
			}
			else
			{
				sector[s].data[0] = size;
				sector[s].data[1] = 0xff;
				fread(&sector[s].data[2], 1, size, f);
				size = 0;
			}
		}
		sector[6+(idx>>2)].words[(idx&3)<<4] = ss;
		sector[6+(idx>>2)].words[((idx&3)<<4) + 1] = count;
		
	}
	
	fclose(f);
	return 0;
}



int readfile(int index)
{
	FILE *f;
	int s, ls, len, j;
	unsigned char name[48];
	unsigned char ch;
	
	if (*name = 0)
		return -1;
	
	if ((index<0) || (index>=40))
		return -1;
	
	if ((s = sector[6+(index>>2)].words[(index&3)<<4]) == 0)
		return -1;
	
	len = 0;
	j = 0;
	
	do
	{
		ch = sector[6+(index>>2)].data[((index&3)<<5) + 4 + j++];
		if ((ch & 0x7f)>=0x20)
			name[len++] = ch & 0x7f;
	} while (j<28 & ch<0x80);
	
	name[len] = 0x00;
	//	strcat(name,".prg");
	
	printf("saving file %s\n",name);
	
	if ( (f = fopen(name,"wb")) == NULL)
	{
		printf("err: fopen [%s]\n",name);
		return -1;
	}
	
	do
	{
		ls = s;
		
		s = sector[s].pointer;
		
		len = 0x7e;
		if (s>=2048)
			len = s & 0x7f;
		
		fwrite(&sector[ls].data[2], 1, len, f);
		
	} while (s < 2048);
	
	fclose(f);
	return 0;
}

int mcfs_load_image(char *argv)
{
	FILE *f;
	int size,i,j;
	
	memset(&sector,0x00,sizeof(sector));
	
	if ( (f = fopen(argv,"rb")) == NULL)
	{
		printf("err: fopen [%s]\n",argv);
		return -1;
	}
	
	size = fread(&sector, 1, sizeof(sector), f);
	fclose(f);
	
	max_sector = size >> 7;
	
	directory();
	
	return 0;
}

NSData *fileWithPath(NSString *path)
{
	NSMutableData *data = [NSMutableData dataWithCapacity:0];
	
	NSString *indexStr = cachedDirectoryContents[[path lastPathComponent]];
	
	int index = [indexStr intValue];
	
	int s, ls, len, j;
	unsigned char name[48];
	unsigned char ch;
	
	
	if ((index<0) || (index>=40))
	{
		return nil;
	}
	
	if ((s = sector[6+(index>>2)].words[(index&3)<<4]) == 0)
	{
		return nil;
	}
	
	len = 0;
	j = 0;
	
	do
	{
		ch = sector[6+(index>>2)].data[((index&3)<<5) + 4 + j++];
		if ((ch & 0x7f)>=0x20)
			name[len++] = ch & 0x7f;
	} while (j<28 & ch<0x80);
	
	name[len] = 0x00;
	
	do
	{
		ls = s;
		
		s = sector[s].pointer;
		
		len = 0x7e;
		if (s>=2048)
			len = s & 0x7f;
		
		[data appendBytes:&sector[ls].data[2] length:len];
		
	} while (s < 2048);
	
	return [NSData dataWithData:data];
}


void directory()
{
	cachedDirectoryContents = @{}.mutableCopy;
	
	int i,j;
	unsigned char ch;
	
	for (i=1; i<40; i++)
	{
		if (sector[6+(i>>2)].words[(i&3)<<4])
		{
			j=0;
			
			NSMutableString *file = [NSMutableString string];
			do
			{
				ch = sector[6+(i>>2)].data[((i&3)<<5) + 4 + j++];
				if ((ch & 0x7f)>=0x20)
				{
					[file appendFormat:@"%c", ch & 0x7f];
				}
				
			} while (j<28 & ch<0x80);
			
			[file appendString:@".prg"];
			
			[cachedDirectoryContents setObject:[NSString stringWithFormat:@"%d", i] forKey:file];
		}
	}
	
}

@implementation MCFSFuseFileSystem

NSAlert *alert = nil;

-(BOOL)loadImage:(NSString *)file
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:file])
	{
		mcfs_load_image([file UTF8String]);
		
		if (is_mcfs())
			return YES;
		else
		{
			alert = [NSAlert alertWithMessageText:@"Unable to open disk" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Disk is not an MCFS disk."];
			
			[alert runModal];
		}
	}
	
	cachedDirectoryContents = nil;
	
	return NO;
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
	return [cachedDirectoryContents allKeys];
}

- (NSData *)contentsAtPath:(NSString *)path {
	
	return fileWithPath(path);
}

#pragma optional Custom Icon

- (NSDictionary *)finderAttributesAtPath:(NSString *)path
                                   error:(NSError **)error {
	
	return nil;
}

- (NSDictionary *)resourceAttributesAtPath:(NSString *)path
                                     error:(NSError **)error {
	
	return nil;
}

@end
