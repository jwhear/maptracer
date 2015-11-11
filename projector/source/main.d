import std.stdio;
import std.algorithm, std.array, std.exception;
import std.string : toStringz;
import shaped.format, shaped.shapefile.reader;

enum Type { Generic, Buildings, Roads, Water }

extern(C)
{
	alias projPJ = void*;
	projPJ pj_init_plus(const(char)* definition);
	void pj_free(projPJ);
	void pj_transform(projPJ src, projPJ dst, long points, int offset,
	                  double* x, double* y, double* z);
	double* zcoord = null;
	enum D2R = 0.017453292519943295769236907684886;
}

void main(string[] args)
{
	string projection = "+proj=merc +ellps=clrk66 +lat_ts=33";
	projPJ pj_input, pj_dest;
	double scale = 1f;  // meters / pixel
	BoundingBox bounds;

	import std.getopt;
	args.getopt(
		"scale", &scale,
		"projection", &projection
	);

    auto shapefiles = args[1..$].map!(path => new File(path).shapefileReader).array;
	if (shapefiles.empty)
		return;  // no files

	// Figure out the bounds of the whole area, projection
	// Build the union of all bounds
	bounds = shapefiles.map!(s => s.bounds).reduce!boundsMax;

	// Convert all component of the bounds to radians for use with pj_transform
	foreach (ref coord; bounds.tupleof)
		coord *= D2R;

	enforce((pj_dest  = pj_init_plus(projection.toStringz())),
	        "Failed to initialize output projection");
	scope(exit) pj_free(pj_dest);

	//TODO Read the PRJ file for the projection info
	enforce((pj_input = pj_init_plus("+proj=latlong +datum=WGS84")),
	        "Failed to initialize input projection");
	scope(exit) pj_free(pj_input);

	pj_transform(pj_input, pj_dest, 2L, 2, &bounds.xmin, &bounds.ymin, zcoord);

	foreach (shapes, const fpath; shapefiles.zip(args[1..$]))
	{
		import std.path;
		const base = fpath.baseName.stripExtension;
		int type = Type.Generic;
		if (base == "buildings")
			type = Type.Buildings;
		else if (base == "roads")
			type = Type.Roads;
		else if (base == "waterways")
			type = Type.Water;

		import derelict.opengl3.ext;
		import std.range;
		auto commands = appender!(ubyte[]);
		auto coords = appender!(float[]);
		void putCoord(PointType)(const ref PointType pt)
		{
			//TODO transform
			auto x = pt.x * D2R;
			auto y = pt.y * D2R;
			pj_transform(pj_input, pj_dest, 1L, 1, &x, &y, zcoord);
			coords.put((x - bounds.xmin)  * scale);
			coords.put((bounds.ymax - y) * scale);
		}

		void addPoly(PolyType)(const ref PolyType poly)
		{
			auto partEnds = chain(poly.partStarts.dropOne, only(poly.points.length));
			foreach (start, end; poly.partStarts.zip(partEnds))
			{
				commands.put(MOVE_TO_NV);
				putCoord(poly.points[start]);

				foreach (const pt; poly.points[start+1..end])
				{
					commands.put(LINE_TO_NV);
					putCoord(pt);
				}

				static if (is(PolyType == Polygon) || is(PolyType == PolygonZ) || is(PolyType == PolygonM))
					commands.put(CLOSE_PATH_NV);
			}
		}

		foreach (shape; shapes)
		{
			switch (shape.type) with (ShapeType)
			{
				case PolyLine:  addPoly(shape._polyline); break;
				case PolyLineZ: addPoly(shape._polylinez); break;
				case PolyLineM: addPoly(shape._polylinem); break;

				case Polygon:   addPoly(shape._polygon); break;
				case PolygonZ:  addPoly(shape._polygonz); break;
				case PolygonM:  addPoly(shape._polygonm); break;

				default:	break;
			}
		}
		ulong[2] lengths = [commands.data.length, coords.data.length];
		stdout.rawWrite(lengths[]);
		stdout.rawWrite(commands.data);
		stdout.rawWrite(coords.data);
	}
}

auto boundsMax(BoundingBox a, BoundingBox b)
{
	BoundingBox ret;
	ret.xmin = min(a.xmin, b.xmin);
	ret.xmax = max(a.xmax, b.xmax);
	ret.ymin = min(a.ymin, b.ymin);
	ret.ymax = max(a.ymax, b.ymax);
	return ret;
}
