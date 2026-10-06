import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/validation.dart';
import 'app_theme.dart';
import 'components.dart';

String persistenceMessage(Object error) {
  if (error is ValidationException) return error.message;
  if (error is DatabaseException) {
    final details = error.toString();
    if (details.contains('units.name_key')) {
      return 'An active unit already has this name. Choose another name or rename the existing unit.';
    }
    if (details.contains('FOREIGN KEY constraint')) {
      return 'This record is in use. Keep its history and deactivate or archive it instead.';
    }
    if (details.contains('Unit is locked')) {
      return 'This item has stock history. Create a new item for a different counting unit.';
    }
    if (details.contains('stock_movements.reversal_of')) {
      return 'This adjustment has already been undone.';
    }
    if (details.contains('archived')) {
      return 'Restore the item and batch before changing stock.';
    }
  }
  return 'Unable to save to this device. Your input is kept. Check available storage, then retry the same save.';
}

/// The same ID survives retries. New input after a failed save gets a new ID.
/// Repositories reconcile successful operations before doing any duplicate write.
class SaveController extends ChangeNotifier {
  bool saving = false;
  bool uncertain = false;
  String? error;
  String operationId = const Uuid().v4();
  bool _disposed = false;
  Future<T?> run<T>(Future<T> Function(String operationId) write) async {
    if (saving) return null;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final result = await write(operationId);
      uncertain = false;
      return result;
    } catch (e) {
      error = persistenceMessage(e);
      uncertain = e is! ValidationException && e is! DatabaseException;
      return null;
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  void newAttempt() {
    if (!saving && !uncertain) {
      operationId = const Uuid().v4();
      error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: ContentText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: .3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ),
        );
}

/// Clean forms retain native route gestures; dirty forms ask before discarding.
class GuardedForm extends StatefulWidget {
  const GuardedForm({
    super.key,
    required this.dirty,
    required this.saving,
    required this.child,
  });
  final bool dirty, saving;
  final Widget child;
  @override
  State<GuardedForm> createState() => _GuardedFormState();
}

class _GuardedFormState extends State<GuardedForm> {
  bool leaving = false, asking = false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!widget.dirty && !widget.saving),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || asking || widget.saving) return;
      asking = true;
      final discard = await confirmAction(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved changes will be lost.',
        action: 'Discard',
        destructive: true,
      );
      asking = false;
      if (discard && context.mounted) {
        setState(() => leaving = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: widget.child,
  );
}

bool validateAndReveal(GlobalKey<FormState> key) {
  final errors = key.currentState!.validateGranularly();
  if (errors.isEmpty) return true;
  Scrollable.ensureVisible(
    errors.first.context,
    duration: reduceMotion(errors.first.context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    alignment: 0.15,
  );
  return false;
}

class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.save,
    required this.onSave,
    required this.dirty,
    this.saveLabel = 'Save',
    this.canSave = true,
  });
  final String title, saveLabel;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final SaveController save;
  final VoidCallback onSave;
  final bool dirty, canSave;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: save,
    builder: (context, _) => GuardedForm(
      dirty: dirty,
      saving: save.saving,
      child: Scaffold(
        appBar: pageAppBar(context, title: title),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: FormViewport(
                hasError: save.error != null,
                content: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ExcludeFocus(
                    excluding: save.saving || save.uncertain,
                    child: IgnorePointer(
                      ignoring: save.saving || save.uncertain,
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ),
                  ),
                ),
                footer: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (save.error != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                            child: ErrorNotice(save.error),
                          ),
                        ),
                      FilledButton(
                        onPressed: save.saving || !canSave
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                onSave();
                              },
                        child: Semantics(
                          liveRegion: true,
                          child: Text(save.saving ? 'Saving…' : saveLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Keep Save within reach; in short keyboard/landscape viewports let the entire
/// form scroll instead of squeezing its fields to zero height.
class FormViewport extends StatelessWidget {
  const FormViewport({
    super.key,
    required this.content,
    required this.footer,
    this.hasError = false,
  });
  final Widget content, footer;
  final bool hasError;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxHeight < (hasError ? 260 : 140)) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [content, footer],
          ),
        );
      }
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: content,
            ),
          ),
          footer,
        ],
      );
    },
  );
}
