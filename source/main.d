
import std.stdio;

import derelict.opengl3.gl3;
import derelict.opengl3.gl;
import derelict.glfw3.glfw3;
import shaped.format, shaped.geometry;

void main(string[] args)
{
	import std.getopt;
	string mapDirectory;
	bool fullscreen = false;

	args.getopt(
		"fullscreen", &fullscreen
	);

	enum Type { Generic, Buildings, Roads, Water }

	// Feature styling, TODO: specify this in a file
	auto styles = [
		Type.Generic:   Styles(2f, true, Color("#888888"), Color("#c0c0b8")),
		Type.Buildings: Styles(2f, true, Color("#885040"), Color("#c0c0b8")),
		Type.Roads:     Styles(1f, false, Color("#885040")),
		Type.Water:     Styles(1f, true, Color("#000033"), Color("#334060"))
	];

	stderr.writeln("Setting up OpenGL context");
	DerelictGLFW3.load();
	DerelictGL3.load();

	if (!glfwInit())
		throw new Exception("Failed to initialize GLFW");
	scope(exit) glfwTerminate();

	glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);

	auto monitor = fullscreen? glfwGetPrimaryMonitor() : null;
	auto window = glfwCreateWindow(600, 400, "MapTrace", monitor, null);
	if (window is null)
		throw new Exception("Failed to create a window/context");
	scope(exit) glfwDestroyWindow(window);

	/* if (!glfwExtensionSupported("GL_NV_path_rendering")) */
	/* 	throw new Exception("No path rendering extension"); */

	glfwMakeContextCurrent(window);

	// Load modern GL and extensions
	auto glversion = DerelictGL3.reload();

	if (!NV_path_rendering)
		writeln("Sorry, I need NV_path_rendering to run");

	//TODO test for path rendering extensions

	// Width and height in pixels (not the same as screen coordinates)
	int width, height;
	glfwGetFramebufferSize(window, &width, &height);

	// Notification on key press
	glfwSetKeyCallback(window, &onKeyPress);

	if (args.length < 2)
	{
		writeln("No path file specified");
		return;
	}

	Path[] layers;
	auto source = File(args[1]);
	while (!source.eof)
	{
		ulong[2] lengths;
		source.rawRead(lengths[]);
		auto commands = minimallyInitializeArray!(ubyte[])(lengths[0]);
		auto coords = minimallyInitializeArray!(float[])(lengths[1]);
	}

	while (!glfwWindowShouldClose(window))
	{
		glClearStencil(0);
		glClearColor(0.2,0.3,0,1);
		glStencilMask(~0);
		glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

		glEnable(GL_STENCIL_TEST);
		glStencilFunc(GL_NOTEQUAL, 0, 0x1f);
		glStencilOp(GL_KEEP, GL_KEEP, GL_ZERO);

		//TODO
		// Set up the view.  In particular, we need to map the current lat, long window
		//  to the viewport

		// render
		foreach (const layer; map.layers)
		{
			if (layer.styles.filled)
			{
				glColor4ubv(layer.styles.fill.components.ptr);
				glStencilFillPathNV(layer.path, GL_COUNT_UP_NV, 0x1F);
				glCoverFillPathNV(layer.path, GL_BOUNDING_BOX_NV);
			}

			if (layer.styles.lineWidth > 0f)
			{
				const GLint reference = 0x1;
				glColor4ubv(layer.styles.line.components.ptr);
				glStencilStrokePathNV(layer.path, reference, 0x1F);
				glCoverStrokePathNV(layer.path, GL_BOUNDING_BOX_NV);
			}
		}

		glfwSwapBuffers(window);
		glfwPollEvents();
	}
	
}

Path pathFromShapes(const Shape[] shapes)
{
	import std.array, std.algorithm, std.range;
	auto commands = appender!(GLubyte[]);
	auto coords = appender!(GLfloat[]);

	void putCoord(PointType)(const ref PointType pt)
	{
		coords.put(pt.x);
		coords.put(pt.y);
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

	auto path = glGenPathsNV(1);
	glPathCommandsNV(path,
		cast(GLsizei)commands.data.length, commands.data.ptr,
		cast(GLsizei)coords.data.length, GL_FLOAT, coords.data.ptr);
	return path;
}

alias Path = uint;

struct Styles
{
	float lineWidth;
	bool filled;
	Color line, fill;
}

struct Color
{
	ubyte[4] components = [255, 255, 255, 255];
	
	this(string hex)
	{
		import std.algorithm : startsWith;
		import std.conv;
		if (!hex.startsWith("#") || hex.length < 7 || hex.length > 9)
			throw new Exception("Unknown color format");
		components[0] = hex[1..3].to!ubyte(16);
		components[1] = hex[3..5].to!ubyte(16);
		components[2] = hex[5..7].to!ubyte(16);

		if (hex.length == 9)
			components[3] = hex[7..9].to!ubyte(16);
	}
}


// GLFW callbacks
extern(C):

void glfwError(int error, const char* description)
{
	import std.string : fromStringz;
	writeln("GLFW (", error, "): ", description.fromStringz);
}

void onKeyPress(GLFWwindow* window, int key, int scancode, int action, int mods)
	nothrow
{
	if (key == GLFW_KEY_ESCAPE)
		glfwSetWindowShouldClose(window, GL_TRUE);
}
