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
      home: Scaffold(
        body: Row(
          children: [
            // 왼쪽 영역
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LeftPanel(key: leftPanelKey), 
              ),
            ),

            // 오른쪽 영역
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

  //변수 
  bool enableOpenGL = true;
  bool autoLink = true;
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
  List<String> generatorOptions = ["Visual Studio 17 2022", "Visual Studio 16 2019", "Ninja", "MinGW Makefiles", "MSYS Makefiles"];
  // 라이브러리 목록을 가져오는 함수
  List<String> getCachedLibraries() {
    final projectRoot = _getProjectRoot();
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

  // 빌드 폴더를 완전히 비우는 함수
  Future<void> _performClean(String buildPath) async {
    final dir = Directory(buildPath);
    if (await dir.exists()) {
      addLog("Clean Build 활성화: 기존 빌드 데이터를 삭제합니다...");
      try {
        //디렉토리 삭제
        await dir.delete(recursive: true);
        
        //삭제 후 즉시 다시 생성
        await dir.create(recursive: true);
        
        addLog("성공: 빌드 폴더가 완전히 초기화되었습니다.");
      } catch (e) {
        // 윈도우 파일 잠금 에러 등에 대한 안내
        addLog("에러: 빌드 폴더를 삭제할 수 없습니다. 실행 중인 프로그램을 종료하거나 폴더를 사용하는 창을 닫아주세요.", isError: true);
      }
    } else {
      // 폴더가 없으면 그냥 새로 생성
      await dir.create(recursive: true);
    }
  }

  //소스 디렉토리 선택
  Future<void> pickSourceFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();

    if (path != null) {
      setState(() {
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

  //빌드 디렉토리 선택
  Future<void> pickBuildFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();

    if (path != null) {
      setState(() {
        buildController.text = path;
      });
    }
  }

  // 프로젝트 생성 함수 
  Future<void> createProject() async {
    setState(() => isLoading = true);
    try{
      final projectName = projectNameController.text.trim();
      final sourcePath = sourceController.text.trim();
      final buildPath = buildController.text.trim();

      if (projectName.isEmpty || sourcePath.isEmpty || buildPath.isEmpty) {
        addLog("Error: 모든 값을 입력하세요.");
        return;
      }

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
          // .cpp 파일이나 기존 CMakeLists.txt가 있으면 기존 프로젝트로 간주 
          if (files.any((file) => file.path.endsWith('.cpp') || file.path.contains('CMakeLists.txt'))) {
            isNewProject = false;
            addLog("기존 프로젝트 감지: 환경 설정 및 의존성을 업데이트합니다.");
          }
        } else {
          await projectDir.create(recursive: true);
          addLog("새 프로젝트 폴더를 생성했습니다.");
        }

        // 기본 구조 생성
        final srcDir = Directory(p.join(projectRoot, 'src'));
        final extDir = Directory(p.join(projectRoot, 'external'));
        if (!await srcDir.exists()) await srcDir.create();
        if (!await extDir.exists()) await extDir.create();

        addLog("GDM 라이브러리 통합 관리자 확인 중...");
        final gdmDir = Directory(p.join(extDir.path, 'gdm'));

        if (!await gdmDir.exists()) {
          addLog("GDM 라이브러리를 최적화하여 다운로드 중...");

          var result = await Process.run('git', [
            'clone',
            '-b', 'master',
            '--single-branch',
            '--depth', '1', // 최신 커밋 하나만 가져오기
            'https://github.com/awidesky/gdm.git',
            gdmDir.path
          ]);

          if (result.exitCode != 0) {
            addLog("Git Clone 실패: ${result.stderr}");
            return;
          }

          // 다운로드 완료 후 .git 폴더 삭제
          final dotGitDir = Directory(p.join(gdmDir.path, '.git'));
          if (await dotGitDir.exists()) {
            await dotGitDir.delete(recursive: true);
            addLog("GDM 최적화 완료 (.git 히스토리 제거됨)");
          }
        }

        //main.cpp 생성
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
        }

      // CMakeLists.txt 생성
      String cmakeContent = '''
cmake_minimum_required(VERSION 3.10)
project($projectName)

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

    cmakeContent += '''
file(GLOB SOURCES "src/*.cpp")
add_executable($projectName \${SOURCES})

if (MSVC)
    add_compile_options(/utf-8 /Zc:__cplusplus)
    set_property(DIRECTORY \${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT $projectName)
endif()
  ''';

      //Auto Link Libraries 체크박스까지 켜져 있을 때만 링크 수행
      if (enableOpenGL && autoLink) {
        cmakeContent += '\ntarget_link_libraries($projectName PRIVATE gdm::deps gdm::glutil)\n';
      }

      addLog("CMakeLists.txt 구성 중...");
      final cmakeFile = File(p.join(projectRoot, 'CMakeLists.txt'));
      await cmakeFile.writeAsString(cmakeContent.trim());
      } catch (e) {
        addLog("오류 발생: $e");
      }

      addLog("프로젝트 구성이 완료되었습니다. 이제 Run CMake와 Build를 진행하세요.");
    } finally {
      setState(() => isLoading = false);
    }
  }

  //로그 추가 함수
  void addLog(String message, {bool isError = false}) {
    bool errorFlag = isError;

    if (!errorFlag) {
      String lowerMsg = message.toLowerCase();
  
      bool hasErrorKeyword = lowerMsg.contains("error") || lowerMsg.contains("failed");
    
      bool isCmakeCheck = lowerMsg.contains("-- performing test") || 
                          lowerMsg.contains("-- looking for");

      if (hasErrorKeyword && !isCmakeCheck) {
        errorFlag = true;
      }
    }

    setState(() {
      logs.add(LogEntry(message, isError: errorFlag));
    });
    
    // 자동 스크롤 로직
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }


  //CMake 실행 함수
  Future<void> runCMake(String projectPath, String buildPath) async {
    try {
      addLog("CMake 실행 시작");

      var result1 = await Process.run(
        'cmake',
        ['-S', projectPath, '-B', buildPath],
      );

      addLog(result1.stdout);
      addLog(result1.stderr);

      var result2 = await Process.run(
        'cmake',
        ['--build', buildPath, '--config', 'Debug'],
      );

      addLog(result2.stdout);
      addLog(result2.stderr);

      addLog("빌드 완료!");
    } catch (e) {
      addLog("에러 발생: $e");
    }
  }

  // 프로젝트 실행
  Future<void> runProject() async {
    final projectName = projectNameController.text.trim();
    final buildPath = buildController.text.trim();
    String exePath = p.join(buildPath, selectedConfig, '$projectName.exe');

    if (await File(exePath).exists()) {
      addLog("--- 실행 시도: $exePath ---");
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
          addLog("[ERROR] ${data.trim()}");
        });
        // 프로세스 종료 감지
        process.exitCode.then((code) {
          addLog("--- 프로세스 종료 (Exit Code: $code) ---");
        });

      } catch (e) {
        addLog("실행 중 심각한 오류 발생: $e");
      }
    } else {
      addLog("에러: $selectedConfig 모드로 빌드된 실행 파일을 찾을 수 없습니다.", isError: true);
    }
  }

  //CMake Generate 함수
  Future<void> runCMakeGenerate() async { 
    setState(() => isLoading = true);
    try{
      final sourcePath = sourceController.text.trim();
      final buildPath = buildController.text.trim();

      if (buildPath.isEmpty) return;

      if (cleanBuild) {
          await _performClean(buildPath);
        } else {
          final cacheFile = File(p.join(buildPath, 'CMakeCache.txt'));
          if (await cacheFile.exists()) {
            await cacheFile.delete();
            addLog("기존 CMake 캐시를 삭제했습니다.");
          }
        }
      final projectRoot = _getProjectRoot();

      //기존 CMamke 캐시 삭제
      final cacheFile = File(p.join(buildPath, 'CMakeCache.txt'));
      if (await cacheFile.exists()) {
        addLog("기존 CMake 캐시를 삭제하고 재구성합니다...");
        await cacheFile.delete();
      }
      
      addLog("CMake 구성을 시작합니다... (Generator: $selectedGenerator)");
      
      try {
        final process = await Process.start('cmake', [
          '-G', selectedGenerator,
          '-S', projectRoot, 
          '-B', buildPath
        ]);

        process.stdout.transform(utf8.decoder).listen((data) { addLog(data.trim()); });
        process.stderr.transform(utf8.decoder).listen((data) { addLog("[ERROR] $data"); });

        final code = await process.exitCode;
        if (code != 0) {
          addLog("에러: $code");
        } else {
          addLog("CMake 구성(Configure/Generate) 완료!");
        }
      } catch (e) {
        addLog("에러 발생: $e", isError: true);
      }
    }finally{
      setState(() => isLoading = false);
    }
  }

  //CMake Build 전용 함수
  Future<void> runCMakeBuild() async {
    setState(() => isLoading = true);
    try{
      final projectName = projectNameController.text.trim();
      final projectRoot = _getProjectRoot();
      final buildPath = buildController.text.trim();
      
      if (buildPath.isEmpty) return;

      addLog("빌드를 시작합니다... (Mode: $selectedConfig)");
      final result = await Process.run('cmake', ['--build', buildPath, '--config', selectedConfig]);
      addLog(result.stdout);

      if (result.exitCode == 0) {
        addLog("빌드 성공! 의존성 파일(DLL) 확인 중...");
        await _deployDependencies(projectRoot, buildPath, projectName);
        addLog("빌드 및 환경 구성 완료!");
      } else {
        addLog("빌드 실패: ${result.stderr}");
      }
    }finally {
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
        addLog("의존성 복사 완료: $fileName");
      }
    }
  }

  //빌드 폴더 열기 기능
  Future<void> openBuildFolder() async {
    final buildPath = buildController.text.trim();
    if (buildPath.isEmpty) return;

    if (await Directory(buildPath).exists()) {
      await Process.run('explorer.exe', [buildPath]);
    } else {
      addLog("에러: 빌드 폴더가 존재하지 않습니다.");
    }
  }

  Future<void> applyOpenGLPreset() async {
    final projectRoot = _getProjectRoot();
    final mainCpp = File(p.join(projectRoot, 'src', 'main.cpp'));

    //확인 팝업
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("프리셋 적용"),
        content: const Text("기존 main.cpp의 내용이 OpenGL 템플릿으로 교체됩니다. 계속하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("적용")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (!await mainCpp.parent.exists()) await mainCpp.parent.create(recursive: true);
        await mainCpp.writeAsString(openGLTemplate);
        addLog("성공: OpenGL 기본 템플릿이 적용되었습니다. 다시 Build 해주세요.");
      } catch (e) {
        addLog("에러: 프리셋 적용 중 오류 발생 - $e");
      }
    }
  }

  //테이블 생성
  List<DataRow> _buildLibraryRows() {
    return getCachedLibraries().map((lib) {
      List<String> parts = lib.split('-');
      String name = parts[0];
      // 버전 정보가 없으면 'Internal' 혹은 'Unknown'으로 표시
      String version = parts.length > 1 ? parts[1] : "Internal";
      return DataRow(cells: [
        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
        DataCell(Text(version)),
        const DataCell(
          Icon(Icons.check_circle, color: Colors.green, size: 18),
        ),
      ]);
    }).toList();
  }

  //위젯
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 프로젝트 정보 입력 영역 (Card로 그룹화)
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

        // 2. 빌드 옵션 설정 영역 (Wrap으로 가독성 개선)
        _buildSectionTitle("Build Configuration"),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildCheckbox("Enable OpenGL", enableOpenGL, "OpenGL 및 관련 라이브러리 활성화 여부를 결정합니다.", (v) => setState(() => enableOpenGL = v!)),
              _buildCheckbox("Auto Link", autoLink, "CMake에서 라이브러리를 자동으로 실행 파일에 연결합니다.", (v) => setState(() => autoLink = v!)),
              _buildCheckbox("Clean Build", cleanBuild, "기존 빌드 캐시를 완전히 삭제하고 새로 구성합니다.", (v) => setState(() => cleanBuild = v!)),
              const SizedBox(width: 10, child: VerticalDivider()),
              _buildCustomDropdown(selectedConfig, configOptions, (v) => setState(() => selectedConfig = v!)),
              _buildCustomDropdown(selectedGenerator, generatorOptions, (v) => setState(() => selectedGenerator = v!), isSmall: true),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. Detected Libraries 테이블 (상단 고정 제목 추가)
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

        // build 함수 내 로그 영역 수정
        // build 함수 내 로그 영역 (기존 코드 655라인 부근 대체)
        _buildSectionTitle("Output Log"),
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            // Padding을 추가하여 스크롤바와 텍스트 사이의 간격을 확보합니다.
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0), 
              child: RawScrollbar( // Scrollbar보다 제어가 쉬운 RawScrollbar 사용 권장
                controller: _scrollController,
                thumbColor: Colors.grey[600], // 스크롤바 색상 명시
                radius: const Radius.circular(8),
                thickness: 8,
                thumbVisibility: true, // 항상 스크롤바 표시
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
                          style: TextStyle( // logs[index].isError 조건 반영
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

  // 텍스트 입력 필드
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

  // 경로 선택 필드
  Widget _buildPathField(String label, TextEditingController controller, VoidCallback onBrowse) {
    return Row(
      children: [
        Expanded(child: _buildInputField(label, controller)),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: onBrowse, child: const Text("Browse")),
      ],
    );
  }

  // 체크박스 스타일
  Widget _buildCheckbox(String label, bool value, String message, Function(bool?) onChanged) {
    return Tooltip(
      message: message, // 표시할 설명 문구
      waitDuration: const Duration(milliseconds: 500), // 마우스를 올리고 대기하는 시간
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: onChanged, visualDensity: VisualDensity.compact),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }


  // 드롭다운 스타일 (그림자 및 테두리 문제 해결)
  Widget _buildCustomDropdown(String value, List<String> options, Function(String?) onChanged, {bool isSmall = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 32, // 실제 화면에 보이는 버튼의 높이
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[400]!),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true, // 버튼 내부의 여백을 최소화하여 높이(32)에 맞게 압축
          menuMaxHeight: 200, 
          // [수정] itemHeight를 null로 설정하면 에러가 해결됩니다.
          // 팝업 메뉴 아이템의 높이는 기본값(48)을 유지하면서 버튼 크기만 줄어듭니다.
          itemHeight: null, 
          style: TextStyle(fontSize: isSmall ? 11 : 12, color: Colors.black),
          focusColor: Colors.transparent,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: options.map<DropdownMenuItem<String>>((String o) => DropdownMenuItem<String>(
            value: o,
            // 터치 영역(48) 안에서 텍스트가 중앙에 오도록 배치
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
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: onRun, 
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 40), 
            ),
            child: Text("Run Project"),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          const Align(alignment: Alignment.centerLeft, child: Text("Preset Profiles")),
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
                  Text("GLFW + GLAD 기본 창 생성 코드", style: TextStyle(fontSize: 11, color: Colors.grey)),
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


