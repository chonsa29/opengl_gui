import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MyApp());
}

final GlobalKey<_LeftPanelState> leftPanelKey = GlobalKey<_LeftPanelState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GDM CMake Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        body: Row(
          children: [
            // Left Panel Area
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LeftPanel(key: leftPanelKey), 
              ),
            ),

            // Right Panel Area
            Container(
              width: 250,
              color: Colors.grey[100],
              child: RightPanel(
                onConfigure: () => leftPanelKey.currentState?.createProject(), 
                onGenerate: () => leftPanelKey.currentState?.runCMakeGenerate(),
                onBuild: () => leftPanelKey.currentState?.runCMakeBuild(),     
                onOpenFolder: () => leftPanelKey.currentState?.openBuildFolder(), 
                onRun: () => leftPanelKey.currentState?.runProject(),
                onApplyPreset: () => leftPanelKey.currentState?.applyOpenGLPreset(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LogEntry {
  final String message;
  final bool isError;
  LogEntry(this.message, {this.isError = false});
}

class LeftPanel extends StatefulWidget {
  const LeftPanel({super.key});

  @override
  _LeftPanelState createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {
  // Variables (OpenGL and AutoLink are now permanently enabled inside the logic)
  final bool enableOpenGL = true;
  final bool autoLink = true;
  bool cleanBuild = false;
  bool isLoading = false;

  String selectedConfig = "Debug";
  List<String> configOptions = ["Debug", "Release"];

  final TextEditingController sourceController = TextEditingController(); 
  final TextEditingController buildController = TextEditingController(); 
  final TextEditingController projectNameController = TextEditingController(); 
  final ScrollController _scrollController = ScrollController();
  List<LogEntry> logs = []; 

  String selectedGenerator = "Visual Studio 17 2022";
  List<String> generatorOptions = ["Visual Studio 17 2022", "Visual Studio 16 2019", "Ninja"];

  // 수정된 라이브러리 실시간 탐지 함수
  List<String> generatorOptions = ["Visual Studio 17 2022", "Visual Studio 16 2019", "Ninja", "MinGW Makefiles", "MSYS Makefiles"];
  // 라이브러리 목록을 가져오는 함수
  List<String> getCachedLibraries() {
    final projectName = projectNameController.text.trim();
    final sourcePath = sourceController.text.trim();
    final buildPath = buildController.text.trim();
    
    if (projectName.isEmpty || sourcePath.isEmpty) return [];

    // 중복 제거를 위해 Set 사용
    final Set<String> detectedLibraries = {};
    final projectRoot = _getProjectRoot();

    // 1. 소스 폴더 내 고정 external 경로 탐색 (glutil 등 감지)
    final extPath = p.join(projectRoot, 'external', 'gdm', 'external');
    final extDir = Directory(extPath);
    if (extDir.existsSync()) {
      for (var entity in extDir.listSync().whereType<Directory>()) {
        detectedLibraries.add(p.basename(entity.path));
      }
    }

    // 2. 빌드 폴더 내 CMake 의존성 다운로드 경로 탐색 (glfw, glad, glm 등 감지)
    if (buildPath.isNotEmpty) {
      // CMake FetchContent가 일반적으로 사용하는 경로 (_deps)
      final depsPath = p.join(buildPath, '_deps');
      final depsDir = Directory(depsPath);
      if (depsDir.existsSync()) {
        for (var entity in depsDir.listSync().whereType<Directory>()) {
          String name = p.basename(entity.path);
          // -src, -build, -subbuild 등으로 끝나는 접미사를 정리하여 깔끔하게 이름만 추출
          name = name.replaceAll(RegExp(r'-(src|build|subbuild)$'), '');
          detectedLibraries.add(name);
        }
      }
      
      // 혹시 다른 세부 하위 경로에 생성되는 경우 추가 체크
      final gdmDepsPath = p.join(buildPath, '_gdm_deps');
      final gdmDepsDir = Directory(gdmDepsPath);
      if (gdmDepsDir.existsSync()) {
        for (var entity in gdmDepsDir.listSync().whereType<Directory>()) {
          String name = p.basename(entity.path);
          name = name.replaceAll(RegExp(r'-(src|build|subbuild)$'), '');
          detectedLibraries.add(name);
        }
      }
    }

    return detectedLibraries.toList();
    final externalDirs = <String>[];

    // 1️. external 폴더 전체 확인
    final extRoot = Directory(p.join(projectRoot, 'external'));
    if (extRoot.existsSync()) {
      for (var entity in extRoot.listSync().whereType<Directory>()) {
        final dirName = p.basename(entity.path);

        // 2. 만약 gdm/external 하위 폴더가 있으면 거기까지 포함
        if (dirName == 'gdm') {
          final gdmExt = Directory(p.join(entity.path, 'external'));
          if (gdmExt.existsSync()) {
            externalDirs.addAll(
              gdmExt.listSync().whereType<Directory>().map((e) => p.basename(e.path))
            );
          }
        } else {
          externalDirs.add(dirName);
        }
      }
    }

    return externalDirs;
  }
  
  static const String openGLTemplate = r'''
//Instead including headers manually...
//#include <glad/gl.h>
//#include <GLFW/glfw3.h>
//Just include glutil/gl.h!
#include <glutil/gl.hpp>

#include <iostream>
#include <array>

const char* vs = R"(
#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aColor;
out vec3 vColor;
void main() {
    gl_Position = vec4(aPos,1.0);
    vColor = aColor;
})";

const char* fs = R"(
#version 330 core
in vec3 vColor;
out vec4 FragColor;
void main() {
    FragColor = vec4(vColor,1.0);
})";

int main() {
    glfwInit();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(800, 600, "Hello, OpenGL!", nullptr, nullptr);
    if (!window) {
        std::cout << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);

    // GLAD2 Method
    int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) {
        std::cout << "Failed to initialize GLAD" << std::endl;
        return -1;
    }

    std::cout << "OpenGL loaded: " << GLAD_VERSION_MAJOR(version)
              << "." << GLAD_VERSION_MINOR(version) << std::endl;

    std::array<float, 18> vtx = {
        -0.5f,-0.5f,0, 1,0,0,
         0.5f,-0.5f,0, 0,1,0,
         0.0f, 0.5f,0, 0,0,1
    };

    GLuint vao, vbo;
    glGenVertexArrays(1,&vao);
    glGenBuffers(1,&vbo);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER,vbo);
    glBufferData(GL_ARRAY_BUFFER,sizeof(vtx),vtx.data(),GL_STATIC_DRAW);

    glVertexAttribPointer(0,3,GL_FLOAT,GL_FALSE,6*sizeof(float),(void*)0);
    glEnableVertexAttribArray(0);

    glVertexAttribPointer(1,3,GL_FLOAT,GL_FALSE,6*sizeof(float),(void*)(3*sizeof(float)));
    glEnableVertexAttribArray(1);

    GLuint v = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(v, 1, &vs, nullptr);
    glCompileShader(v);
    
    GLuint f = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(f, 1, &fs, nullptr);
    glCompileShader(f);

    GLuint p = glCreateProgram();
    glAttachShader(p, v);
    glAttachShader(p, f);
    glLinkProgram(p);

    glDeleteShader(v);
    glDeleteShader(f);

    while (!glfwWindowShouldClose(window)) {
        glClearColor(0.1f,0.1f,0.2f,1);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram(p);
        glBindVertexArray(vao);
        glDrawArrays(GL_TRIANGLES,0,3);

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glDeleteProgram(p);
    glDeleteBuffers(1,&vbo);
    //glDeleteVertexArrays(1,&vao); //We intentionally introduced a resource leak, can you find it?

    glfwTerminate();
}
''';

  // Clear the build folder completely
  Future<void> _performClean(String buildPath) async {
    final dir = Directory(buildPath);
    if (await dir.exists()) {
      addLog("Clean Build enabled: Deleting existing build data...");
      try {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
        addLog("Success: Build folder has been completely initialized.");
      } catch (e) {
        addLog("Error: Cannot delete build folder. Please close any programs or windows using this folder.", isError: true);
      }
    } else {
      await dir.create(recursive: true);
    }
  }

  // Common validation logic for build paths
  bool _validateInputs() {
    final projectName = projectNameController.text.trim();
    final sourcePath = sourceController.text.trim();
    final buildPath = buildController.text.trim();

    if (projectName.isEmpty || sourcePath.isEmpty || buildPath.isEmpty) {
      addLog("Error: Missing required fields. Please fill in Project Name, Source Directory, and Build Directory.", isError: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all required fields before proceeding."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return false;
    }
    return true;
  }

  // Pick source directory
  Future<void> pickSourceFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();

    if (path != null) {
    if (path != null) {
      setState(() {
        sourceController.text = path;
        
        if (projectNameController.text.isEmpty || projectNameController.text == "NewProject") {
          projectNameController.text = p.basename(path);
        }
        
        // Auto-set build directory to /build
        buildController.text = p.join(path, 'build');
        if (projectNameController.text.isEmpty) {
          projectNameController.text = "NewProject";
        }

        final projectName = projectNameController.text.trim();

        // 선택한 폴더 아래에 프로젝트 폴더를 Source로 설정
        final sourceDir = p.join(path, projectName);

        sourceController.text = sourceDir;
        buildController.text = p.join(sourceDir, 'build');
      });
    }
  }

  // Pick build directory
  Future<void> pickBuildFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();

    if (path != null) {
      setState(() {
        buildController.text = path;
      });
    }
  }

  // Configure Project (Create Project Structure)
  Future<void> createProject() async {
    if (!_validateInputs()) return;

    setState(() => isLoading = true);
    try {
      final projectName = projectNameController.text.trim();
      final sourcePath = sourceController.text.trim();

      String projectRoot;
      if (p.basename(sourcePath) == projectName) {
        projectRoot = sourcePath;
      } else {
        projectRoot = p.join(sourcePath, projectName);
      }

      final projectDir = Directory(projectRoot);

      try {
        addLog("Target directory: $projectRoot");

        bool isNewProject = true;
        if (await projectDir.exists()) {
          final files = projectDir.listSync();
          if (files.any((file) => file.path.endsWith('.cpp') || file.path.contains('CMakeLists.txt'))) {
            isNewProject = false;
            addLog("Existing project detected: Updating environment and dependencies.");
          }
        } else {
          await projectDir.create(recursive: true);
          addLog("Created a new project folder.");
        }

        // Generate base structure
        final srcDir = Directory(p.join(projectRoot, 'src'));
        final extDir = Directory(p.join(projectRoot, 'external'));
        if (!await srcDir.exists()) await srcDir.create();
        if (!await extDir.exists()) await extDir.create();

        addLog("Checking GDM Library Integrated Manager...");
        final gdmDir = Directory(p.join(extDir.path, 'gdm'));

        if (!await gdmDir.exists()) {
          addLog("Downloading optimized GDM library...");

          // Fixed to pull from the default branch (master/main)
          var result = await Process.run('git', [
            'clone',
            '-b', 'master',
            '--single-branch',
            '--depth', '1',
            'https://github.com/awidesky/gdm.git',
            gdmDir.path
          ]);

          if (result.exitCode != 0) {
            addLog("Git Clone failed: ${result.stderr}", isError: true);
            return;
          }

          final dotGitDir = Directory(p.join(gdmDir.path, '.git'));
          if (await dotGitDir.exists()) {
            await dotGitDir.delete(recursive: true);
            addLog("GDM optimization completed (.git history removed).");
          }
        }

        // Generate main.cpp
        final mainCpp = File(p.join(srcDir.path, 'main.cpp'));
        if (isNewProject || !await mainCpp.exists()) {
          addLog("기본 템플릿 소스를 생성합니다.");
          await mainCpp.writeAsString(enableOpenGL ? openGLTemplate : '''
  #include <iostream>
  int main() {
      std::cout << "Hello OpenGL Project!" << std::endl;
      return 0;
  }
  ''');
          addLog("Generating default template source.");
          await mainCpp.writeAsString(r'''
#include <iostream>
int main() {
    std::cout << "Hello OpenGL Project!" << std::endl;
    return 0;
}
''');
        }

      // CMakeLists.txt 생성
      String cmakeContent = '''
cmake_minimum_required(VERSION 3.10)
project($projectName)
        // Generate CMakeLists.txt
        String cmakeContent = '''
cmake_minimum_required(VERSION 3.10)
project($projectName)

set(CMAKE_CXX_STANDARD 17)
add_definitions(-DGLM_ENABLE_EXPERIMENTAL)
''';
set(CMAKE_CXX_STANDARD 17)
add_definitions(-DGLM_ENABLE_EXPERIMENTAL)
''';

    if (enableOpenGL) {cmakeContent += '''
# GDM 옵션
set(GDM_USE_GLUTIL ON CACHE BOOL "" FORCE)
set(GDM_BUILD_EXAMPLES ON CACHE BOOL "" FORCE)

# 윈도우 생성 라이브러리(glfw, freeglut으로 변경 가능)
set(GDM_WINDOW_BACKEND "glfw" CACHE STRING "" FORCE)
set(GLFW_VERSION "3.4.0" CACHE STRING "" FORCE)

# OpenGL 함수 로딩 라이브러리(glad, glew로 변경 가능)
set(GDM_GL_LOADER "glad" CACHE STRING "" FORCE)
set(GLAD_VERSION "2.0.8" CACHE STRING "" FORCE)

# GLSL 수학 라이브러리(glm)
set(GDM_USE_GLM ON CACHE BOOL "" FORCE)
set(GLM_VERSION "1.0.1" CACHE STRING "" FORCE)

# gdm이 옵션으로 설정한 의존성을 처리.
add_subdirectory(external/gdm)
''';
    }
        if (enableOpenGL) {
          cmakeContent += '\n# Add OpenGL related libraries\n';
          cmakeContent += 'add_subdirectory(external/gdm)\n';
          cmakeContent += 'include_directories(external/gdm/include)\n';
        }

        cmakeContent += '''
if (MSVC)
    add_compile_options(/utf-8 /Zc:__cplusplus)
endif()

file(GLOB SOURCES "src/*.cpp")
add_executable($projectName \${SOURCES})
''';
    cmakeContent += '''
file(GLOB SOURCES "src/*.cpp")
add_executable($projectName \${SOURCES})

if (MSVC)
    add_compile_options(/utf-8 /Zc:__cplusplus)
    set_property(DIRECTORY \${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT $projectName)
endif()
  ''';

        if (enableOpenGL && autoLink) {
          cmakeContent += '\ntarget_link_libraries($projectName PRIVATE gdm glfw)\n';
        }
      //Auto Link Libraries 체크박스까지 켜져 있을 때만 링크 수행
      if (enableOpenGL && autoLink) {
        cmakeContent += '\ntarget_link_libraries($projectName PRIVATE gdm::deps gdm::glutil)\n';
      }

        addLog("Configuring CMakeLists.txt...");
        final cmakeFile = File(p.join(projectRoot, 'CMakeLists.txt'));
        await cmakeFile.writeAsString(cmakeContent.trim());
      } catch (e) {
        addLog("An error occurred: $e", isError: true);
      }

      addLog("Project configuration completed. You can now proceed to Generate and Build.");
      addLog("프로젝트 구성이 완료되었습니다. 이제 Run CMake와 Build를 진행하세요.");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Add Log function
  void addLog(String message, {bool isError = false}) {
    bool errorFlag = isError;

    if (!errorFlag) {
      String lowerMsg = message.toLowerCase();
  
      bool hasErrorKeyword = lowerMsg.contains("error:") || 
                            lowerMsg.contains(": error") || 
                            lowerMsg.contains("failed:");
    
      bool isCmakeCheck = lowerMsg.contains("-- performing test") || 
                          lowerMsg.contains("-- looking for");

      if (hasErrorKeyword && !isCmakeCheck) {
        errorFlag = true;
      }
    }

    setState(() {
      logs.add(LogEntry(message, isError: errorFlag));
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // Run Project
  Future<void> runProject() async {
    if (!_validateInputs()) return;

    final projectName = projectNameController.text.trim();
    final buildPath = buildController.text.trim();
    String exePath = p.join(buildPath, selectedConfig, '$projectName.exe');

    if (await File(exePath).exists()) {
      addLog("--- Attempting to run: $exePath ---");
      try {
        final process = await Process.start(
          exePath,
          [],
          workingDirectory: p.dirname(exePath),
        );
        process.stdout.transform(utf8.decoder).listen((data) {
          addLog(data.trim());
        });
        process.stderr.transform(utf8.decoder).listen((data) {
          addLog("[ERROR] ${data.trim()}", isError: true);
        });
        process.exitCode.then((code) {
          addLog("--- Process terminated (Exit Code: $code) ---");
        });
      } catch (e) {
        addLog("Critical error during execution: $e", isError: true);
      }
    } else {
      addLog("Error: Could not find the executable built in $selectedConfig mode.", isError: true);
    }
  }

  // CMake Generate Function
  Future<void> runCMakeGenerate() async { 
    if (!_validateInputs()) return;

    setState(() => isLoading = true);
    try {
      final buildPath = buildController.text.trim();

      if (cleanBuild) {
        await _performClean(buildPath);
      } else {
        final cacheFile = File(p.join(buildPath, 'CMakeCache.txt'));
        if (await cacheFile.exists()) {
          await cacheFile.delete();
          addLog("Deleted existing CMake cache.");
        }
      }
      final projectRoot = _getProjectRoot();

      final cacheFile = File(p.join(buildPath, 'CMakeCache.txt'));
      if (await cacheFile.exists()) {
        addLog("Deleting and reconstructing existing CMake cache...");
        await cacheFile.delete();
      }
      
      addLog("Starting CMake configuration... (Generator: $selectedGenerator)");
      
      try {
        final process = await Process.start('cmake', [
          '-G', selectedGenerator,
          '-S', projectRoot, 
          '-B', buildPath
        ]);

        if (result.stdout.toString().isNotEmpty) addLog(result.stdout);
        
        if (result.exitCode != 0) {
          addLog("Error: ${result.stderr}", isError: true);
        process.stdout.transform(utf8.decoder).listen((data) { addLog(data.trim()); });
        process.stderr.transform(utf8.decoder).listen((data) { addLog("[ERROR] $data"); });

        final code = await process.exitCode;
        if (code != 0) {
          addLog("에러: $code");
        } else {
          addLog("CMake configuration (Generate) completed successfully!");
          addLog("CMake 구성(Configure/Generate) 완료!");
        }
      } catch (e) {
        addLog("Error occurred: $e", isError: true);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  // CMake Build Function
  Future<void> runCMakeBuild() async {
    if (!_validateInputs()) return;

    setState(() => isLoading = true);
    try {
      final projectName = projectNameController.text.trim();
      final projectRoot = _getProjectRoot();
      final buildPath = buildController.text.trim();
      
      addLog("Starting build... (Mode: $selectedConfig)");
      final result = await Process.run('cmake', ['--build', buildPath, '--config', selectedConfig]);
      if (result.stdout.toString().isNotEmpty) addLog(result.stdout);

      if (result.exitCode == 0) {
        addLog("Build successful! Checking dependency files (DLLs)...");
        await _deployDependencies(projectRoot, buildPath, projectName);
        addLog("Build and environment configuration completed!");
      } else {
        addLog("Build failed: ${result.stderr}", isError: true);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _getProjectRoot() {
    final projectName = projectNameController.text.trim();
    final sourcePath = sourceController.text.trim();

    if (p.basename(sourcePath) == projectName) {
      return sourcePath;
    } else {
      return p.join(sourcePath, projectName);
    }
  }
  
  Future<void> _deployDependencies(String projectRoot, String buildPath, String projectName) async {
    final targetDir = Directory(p.join(buildPath, 'Debug'));
    if (!await targetDir.exists()) return;

    final List<String> dllSources = [
      p.join(buildPath, '_deps', 'glfw3-build', 'src', 'Debug', 'glfw3.dll'),
      p.join(buildPath, 'external', 'gdm', 'external', 'glfw3-3.4.0', 'src', 'Debug', 'glfw3.dll'),
    ];

    for (String sourcePath in dllSources) {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        final fileName = p.basename(sourcePath);
        await sourceFile.copy(p.join(targetDir.path, fileName));
        addLog("Dependency copied: $fileName");
      }
    }
  }

  // Open Build Folder Function
  Future<void> openBuildFolder() async {
    if (!_validateInputs()) return;

    final buildPath = buildController.text.trim();
    if (await Directory(buildPath).exists()) {
      await Process.run('explorer.exe', [buildPath]);
    } else {
      addLog("Error: Build folder does not exist.", isError: true);
    }
  }

  Future<void> applyOpenGLPreset() async {
    if (!_validateInputs()) return;

    final projectRoot = _getProjectRoot();
    final mainCpp = File(p.join(projectRoot, 'src', 'main.cpp'));

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apply Preset"),
        content: const Text("The content of main.cpp will be replaced with the OpenGL template. Do you want to continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Apply")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (!await mainCpp.parent.exists()) await mainCpp.parent.create(recursive: true);
        await mainCpp.writeAsString(openGLTemplate);
        addLog("Success: Default OpenGL template applied. Please rebuild the project.");
      } catch (e) {
        addLog("Error: Failed to apply template - $e", isError: true);
      }
    }
  }

  List<DataRow> _buildLibraryRows() {
    final libs = getCachedLibraries();
    if (libs.isEmpty) {
      return [
        const DataRow(cells: [
          DataCell(Text("No libraries detected", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
          DataCell(Text("-")),
          DataCell(Icon(Icons.help_outline, color: Colors.grey, size: 18)),
        ])
      ];
    }

    return libs.map((lib) {
      List<String> parts = lib.split('-');
      String name = parts[0].toUpperCase(); 
      
      String version = "Detected";
      if (parts.length > 1) {
        version = parts.sublist(1).join('-');
      } else if (name == "GLAD") {
        version = "2.0"; 
      }
      
      return DataRow(cells: [
        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
        DataCell(Text(version)),
        const DataCell(
          Icon(Icons.check_circle, color: Colors.green, size: 18),
        ),
      ]);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Project Info
        _buildSectionTitle("Project Information"),
        Card(
          elevation: 0,
          color: Colors.grey[50],
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildInputField("Project Name", projectNameController),
                const SizedBox(height: 10),
                _buildPathField("Source Directory", sourceController, pickSourceFolder),
                const SizedBox(height: 10),
                _buildPathField("Build Directory", buildController, pickBuildFolder),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 2. Build Configuration
        _buildSectionTitle("Build Configuration"),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildCheckbox("Clean Build", cleanBuild, "Completely delete the existing build cache and rebuild.", (v) => setState(() => cleanBuild = v!)),
              const SizedBox(width: 10, child: VerticalDivider()),
              _buildCustomDropdown(selectedConfig, configOptions, (v) => setState(() => selectedConfig = v!)),
              _buildCustomDropdown(selectedGenerator, generatorOptions, (v) => setState(() => selectedGenerator = v!), isSmall: true),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. Detected Libraries
        _buildSectionTitle("Detected Libraries"),
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
                  headingRowHeight: 40,
                  dataRowMinHeight: 35,
                  dataRowMaxHeight: 45,
                  columns: const [
                    DataColumn(label: Text("Library", style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Version", style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _buildLibraryRows(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 4. Output Log
        _buildSectionTitle("Output Log"),
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0), 
              child: RawScrollbar(
                controller: _scrollController,
                thumbColor: Colors.grey[600],
                radius: const Radius.circular(8),
                thickness: 8,
                thumbVisibility: true,
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          logs[index].message,
                          style: TextStyle(
                            color: logs[index].isError ? Colors.redAccent : Colors.greenAccent,
                            fontFamily: 'Consolas',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else
          const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey[700])),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }

  Widget _buildPathField(String label, TextEditingController controller, VoidCallback onBrowse) {
    return Row(
      children: [
        Expanded(child: _buildInputField(label, controller)),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: onBrowse, child: const Text("Browse")),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, String message, Function(bool?) onChanged) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 500),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: onChanged, visualDensity: VisualDensity.compact),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCustomDropdown(String value, List<String> options, Function(String?) onChanged, {bool isSmall = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[400]!),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          menuMaxHeight: 200, 
          itemHeight: null, 
          style: TextStyle(fontSize: isSmall ? 11 : 12, color: Colors.black),
          focusColor: Colors.transparent,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: options.map<DropdownMenuItem<String>>((String o) => DropdownMenuItem<String>(
            value: o,
            child: Text(o),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class RightPanel extends StatelessWidget {
  final VoidCallback onConfigure;
  final VoidCallback onGenerate;
  final VoidCallback onBuild;
  final VoidCallback onOpenFolder;
  final VoidCallback onRun;
  final VoidCallback onApplyPreset;

  const RightPanel({
    super.key, 
    required this.onConfigure,
    required this.onGenerate,
    required this.onBuild,
    required this.onOpenFolder,
    required this.onRun,
    required this.onApplyPreset,
  }); 
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildButton("Make Project", onConfigure),
          const SizedBox(height: 10),
          _buildButton("Run CMake", onGenerate),
          const SizedBox(height: 10),
          _buildButton("Build", onBuild),
          const SizedBox(height: 10),
          _buildButton("Open Build Folder", onOpenFolder),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: onRun, 
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 40), 
            ),
            child: const Text("Run Project"),
          ),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: Text("Preset Profiles", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 10),

          InkWell(
            onTap: onApplyPreset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border.all(color: Colors.blue[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("OpenGL Basic Template", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  SizedBox(height: 5),
                  Text("Generates standard template window using GLFW + GLAD.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
      child: Text(label),
    );
  }
}