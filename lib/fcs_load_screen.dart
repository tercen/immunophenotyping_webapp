

import 'dart:async';
import 'dart:io';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:immunophenotyping_template_assistant/data.dart';
import 'package:immunophenotyping_template_assistant/ui_utils.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:list_picker/list_picker.dart';
import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:web/web.dart' as web;
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:tson/tson.dart' as tson;
import 'package:uuid/uuid.dart';

class FcsLoadScreen extends StatefulWidget {
  final AppData appData;

  const FcsLoadScreen({super.key,  required this.appData});

  @override
  State<FcsLoadScreen> createState()=> _FcsLoadScreenState();

}


//TODO Improve general screen layout
//TODO Fix progress message
//TODO Check existing progress name
//TODO Check file types for drop
//TODO better upload/finished feedback

class UploadFile {
  String filename;
  bool uploaded;

  UploadFile(this.filename, this.uploaded);
}


class _FcsLoadScreenState extends State<FcsLoadScreen>{
  //State vars
  bool finishedUploading = false;
  bool enableUpload = false;

  late ProgressDialog progressDialog = ProgressDialog(context: context);
  
  int total = -1;
  int processed = -1;
  late StreamSubscription<sci.TaskEvent> sub;

  String progress = "";
  final factory = tercen.ServiceFactory();
  late DropzoneViewController dvController;
  late FilePickerResult result;
  String selectedTeam = "Please select a team";
  Color dvBackground = Colors.white;
  List<UploadFile> filesToUpload = [UploadFile("Drag Files Here", false)];
  List<web.File> htmlFileList = [];
  var workflowTfController = TextEditingController(text: "Immunophenotyping Workflow");

  final List<String> teamNameList = [];
  sci.Project project = sci.Project();
  late Map<String, Object> dataHandler;


  List<sci.Project> projectList = [];


  @override
  void initState () {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_){
      _loadTeams();
      
    });

   
  }

  Future<void> _loadTeams() async {
    var token = Uri.base.queryParameters["token"] ?? '';
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

    List<sci.Team> teamList = await factory.teamService.findTeamByOwner(keys: [decodedToken["data"]["u"]]);

      for( var team in teamList){
      teamNameList.add(team.name);
    }

  }


  List<Widget> _buildFileList(){
    List<Widget> wdgList = [];
    for(int i = 0; i < filesToUpload.length; i++){
      if( filesToUpload[i].filename != "Drag Files Here"){
        Row entry = Row(
          children: [
            filesToUpload[i].uploaded 
                  ? const Icon(Icons.check) 
                  : InkWell(
                        child: const Icon(Icons.delete),
                        onTap: () {
                          setState(() {
                            filesToUpload.removeAt(i);  
                          });
                          
                        },
                    ), 
            Text(filesToUpload[i].filename, style: const TextStyle(fontSize: 14, color: Colors.black45))
          ],
        );           
        wdgList.add(entry);
      }else{
        wdgList.add(Text(filesToUpload[i].filename, style: const TextStyle(fontSize: 14, color: Colors.black45)));
      }
    }

    return wdgList;
  }

  void _updateFilesToUpload(web.File wf){
    if( filesToUpload[0].filename == "Drag Files Here"){
      filesToUpload.removeAt(0);
    }
    filesToUpload.add(UploadFile(wf.name, false));

    htmlFileList.add(wf);
  }


  void _uploadFiles() async {
    var uuid = const Uuid();


    // Create a project to store the workflow
    if( project.id == "" ){
      var projectList = await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(startKey: selectedTeam, endKey: selectedTeam);
      bool createProject = true;
      for( var proj in projectList){
        if(proj.name == workflowTfController.text){
          project = proj;
          createProject = false;
        }
      }

      if( createProject == true ){
        project.name = workflowTfController.text;
        project.acl.owner = selectedTeam;
        project = await factory.projectService.create(project);
      }
      
    }

    List<sci.FileDocument> uploadedDocs = [];
    List<String> docIds = [];
    List<String> dotDocIds = [];
    
    for( int i = 0; i < htmlFileList.length; i++ ){
      web.File file = htmlFileList[i];
      var bytes = await dvController.getFileData(file);
      sci.FileDocument docToUpload = sci.FileDocument()
              ..name = file.name
              ..projectId = project.id
              ..acl.owner = selectedTeam;

      uploadedDocs.add( await factory.fileService.upload(docToUpload, Stream.fromIterable([bytes]) ) );

      setState(() {
        filesToUpload[i].uploaded = true;
      });

      docIds.add(uploadedDocs[i].id);
      dotDocIds.add(uuid.v4());
    }

    // Reading FCS
    // 1. Get operator
    var installedOperators = await factory.documentService.findOperatorByOwnerLastModifiedDate(startKey: selectedTeam, endKey: '');
    sci.Document op = sci.Document();
    for( var o in installedOperators ){
      if( o.name == "FCS"){
        op = o;
      }
    }


    // 2. Prepare the computation task
    sci.CubeQuery query = sci.CubeQuery();
    query.operatorSettings.operatorRef.operatorId = op.id;
    query.operatorSettings.operatorRef.operatorKind = op.kind;
    query.operatorSettings.operatorRef.name = op.name;

    // Query Projection
    sci.Factor docFactor = sci.Factor()
            ..name = "documentId"
            ..type = "string";

    query.colColumns.add(docFactor);


    // Data to feed projection
    sci.Table tbl = sci.Table();

    sci.Column col = sci.Column()
          ..name = "documentId"
          ..type = "string"
          ..id = "documentId"
          ..nRows = 1
          ..size = -1
          ..values = tson.CStringList.fromList(dotDocIds);
    
    tbl.columns.add(col);

    col = sci.Column()
          ..name = ".documentId"
          ..type = "string"
          ..id = ".documentId"
          ..nRows = 1
          ..size = -1
          ..values = tson.CStringList.fromList(docIds);
    
    tbl.columns.add(col);

    var id = uuid.v4();
    sci.InMemoryRelation rel = sci.InMemoryRelation()
            ..id = id
            ..inMemoryTable = tbl;

    query.relation = rel;
    query.axisQueries.add(sci.CubeAxisQuery());
    

    sci.RunComputationTask compTask = sci.RunComputationTask()
          ..state = sci.InitState()
          ..owner = selectedTeam
          ..query = query
          ..projectId = project.id;
    
    

    compTask = await factory.taskService.create(compTask) as sci.RunComputationTask;


    var taskStream = factory.eventService.listenTaskChannel(compTask.id, true).asBroadcastStream();
    
    //{kind: TaskProgressEvent, id: , isDeleted: false, rev: ,
    // date: {kind: Date, value: 2024-07-11T16:29:54.226033Z}, taskId: 3adc6ed4b2e0e95f81fa2488033fb5f9, message: measurement, total: 8, actual: 2}
    // var currentFile = "";


    sub = taskStream.listen((evt){
      var evtMap = evt.toJson();
      if(evtMap["kind"] == "TaskProgressEvent"){
        // setState(() {
        //   print(evtMap);
        //   if( currentFile != uploadedDocs[0].name){
        //     currentFile = uploadedDocs[0].name;
        //     if(progressDialog.isOpen()){
        //       progressDialog.close();
        //     }
            
        //     progressDialog.show(
        //           completed: null,
        //           msg: "Processing file ${uploadedDocs[0].name}", 
        //           max: evtMap["total"] as int,
        //           barrierColor: const Color.fromARGB(125, 0, 0, 0));
        //   }
        //   progressDialog.update(value: evtMap["actual"] as int);
        // });
      }
    });


      
// try {
//   await for (var evt in stream) {
//     state.taskState = evt.state;
//   }
// } catch (e) {
//   state
//     ..taskId = ''
//     ..taskState = FailedState.fromError(e);

//   (state.taskState as FailedState).throwError();

//   return;
// }
      

    sub.onDone((){
      _getComputedRelation(compTask.id);
      
      finishedUploading = true;
    });

  }


  void _getComputedRelation(String taskId) async{
    var compTask = await factory.taskService.get(taskId) as sci.RunComputationTask;
    // sci.CompositeRelation rel = compTask.computedRelation as sci.CompositeRelation;
    // print(rel.toJson());
    // sci.CompositeRelation cr = rel.joinOperators[0].rightRelation as sci.CompositeRelation;
    // sci.Schema sch = await factory.tableSchemaService.get(cr.joinOperators[0].rightRelation.id);
    // print(sch.toJson());


    List<sci.ProjectDocument> projObjs = await factory.projectDocumentService.findProjectObjectsByFolderAndName(startKey: [project.id, "ufff0", "ufff0"], endKey: [project.id, "", ""]);

    for( var po in projObjs ){
      //TODO Need to check for && po.name.contains(uploadedFiledoc name ...)
      if(po.name.contains( "Channel-Descriptions" )  ){
        sci.Schema sch = await factory.tableSchemaService.get(po.id);
        sci.Table res = await factory.tableSchemaService.select(sch.id, ["channel_name", "channel_description"], 0, sch.nRows);
        widget.appData.channelAnnotationTbl = res;
        widget.appData.channelAnnotationDoc = po;
      }
    }
    // print("Selecting");
    // sci.Table tbl = await factory.tableSchemaService.select(sch.id, ["filename", ".content"], 0, 1);
    // print(tbl.toJson());
    // _tryToPrint(rel.mainRelation.id, "rel.mainRelation.id");
    // 
    // _tryToPrint(cr.joinOperators[0].rightRelation.id, "rel.joinOperators[0]...rightRelation.id"); 
    // _tryToPrint(rel.joinOperators[1].rightRelation.id, "rel.joinOperators[1].rightRelation.id"); // Summary
    
  }

  
  void  _processSingleFileDrop(ev){
    if (ev is web.File) {
      setState(() {
        _updateFilesToUpload(ev);
      });
      // final bytes = await controller1.getFileData(ev);
      // print(bytes.sublist(0, min(bytes.length, 20)));
    } 
  }

  void _doUpload(){
    finishedUploading = false;


    progressDialog.show(msg: "Reading FCS files, please wait", barrierColor: const Color.fromARGB(125, 0, 0, 0));
    
    _uploadFiles();

    Timer.periodic(const Duration(milliseconds: 250), (tmr){
      if( finishedUploading == true){
        tmr.cancel();
        sub.cancel();

        if( progressDialog.isOpen()){
          progressDialog.close();
          setState(() {
            enableUpload = false;
          });
        }
        
      }
    });

  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        children: [
          addAlignedWidget(
            // const Text("Immunophenotyping Workflow", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),)
            TextField(
              controller: workflowTfController,
              onTapOutside: null, // Should check availability
              decoration: 
                const InputDecoration(
                  border: UnderlineInputBorder(),

                ),
            )
          ),

          addSeparator(),

          addAlignedWidget(ElevatedButton(
              child: const Text("Select Team"),
              onPressed: ()  async {
                String team = ( await showPickerDialog(
                  context: context,
                  label: "",
                  items: teamNameList,
                ))!;

                setState(() {
                  selectedTeam = team;
                  enableUpload = true;
                });
                // teamTfController.text = selectedTeam;
              }
            ),
          ),


          addSeparator(spacing: "small"),
          

          addAlignedWidget(Material( 
              child: 
              Text(
                selectedTeam, 
                style: 
                  const TextStyle(fontSize: 16, color: Colors.black)
              ),
            ) 
          ),
         

          addSeparator(spacing: "intermediate"),

          addAlignedWidget(const Text("Upload FCS Files.", style: TextStyle(fontSize: 16, color: Colors.black),)),

          addSeparator(spacing: "small"),

          addAlignedWidget(
            Table(
              columnWidths: const {
                0: FixedColumnWidth(30),
                1: IntrinsicColumnWidth()
              },
              children: [
                TableRow(
                  children: [
                    Material( 
                      child: InkWell(
                        onTap: () async {
                          result = (await FilePicker.platform.pickFiles())!;
                        },
                        child: const Icon(Icons.add_circle_outline_rounded),
                      )
                    ),
                    const Text("Choose Files", style: TextStyle(fontSize: 16, color: Colors.black),)
                  ]
                )
              ],
            )
          ),


          addSeparator(spacing: "small"),


          addAlignedWidget(
            Stack(
              children: [
                SizedBox(
                  height: 200,
                  width: 400,

                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey), borderRadius: BorderRadius.circular(2.0),color: dvBackground,),
                    child: ListView(
                      scrollDirection: Axis.vertical,
                      children: _buildFileList(),
                    ),
                  )
                ),

                SizedBox(
                  height: 200,
                  width: 400,
                  child: 
                    DropzoneView(
                      
                      operation: DragOperation.copy,
                      onCreated: (ctrl) => dvController = ctrl,
                      onLeave: () {
                        setState(() {
                          dvBackground = Colors.white;
                        });
                      },
                      onHover: () {
                        setState(() {
                          dvBackground = Colors.cyan.shade50;
                        });
                      },
                      onDrop:  (ev) async => _processSingleFileDrop(ev),
                      onDropMultiple: (dynamic ev) => (List<dynamic> ev) => print('Drop multiple: $ev'),
                    ),
                )
              ],
            )
          ),

          addSeparator(spacing: "small"),

          addAlignedWidget(
            ElevatedButton(
                style: enableUpload 
                ? setButtonStyle("enabled")
                : setButtonStyle("disabled"),
                onPressed: () {
                  enableUpload 
                  ? _doUpload()
                  : null;
                },
 
                child: const Text("Upload")
            )
          ),

        ],
      ),
    );
 
  }

}