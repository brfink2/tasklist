-- ENUMS
CREATE TYPE membership_role AS ENUM ('owner', 'director', 'manager', 'staff');
CREATE TYPE membership_status AS ENUM ('active', 'invited', 'disabled');
CREATE TYPE list_scope AS ENUM ('center', 'room', 'either');
CREATE TYPE frequency AS ENUM ('daily', 'weekly', 'monthly', 'quarterly', 'yearly');
CREATE TYPE assignee_type AS ENUM ('role', 'user', 'room');
CREATE TYPE task_ref_type AS ENUM ('base', 'override');
CREATE TYPE completion_status AS ENUM ('completed', 'skipped', 'na');

-- TABLES

CREATE TABLE groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE centers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id uuid REFERENCES groups(id),
    name text NOT NULL,
    timezone text NOT NULL DEFAULT 'America/Chicago',
    created_at timestamptz DEFAULT now()
);

CREATE TABLE rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    center_id uuid NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
    name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE center_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    center_id uuid NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    role membership_role NOT NULL,
    status membership_status NOT NULL DEFAULT 'active',
    created_at timestamptz DEFAULT now(),
    UNIQUE(center_id, user_id)
);

CREATE TABLE template_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    description text,
    scope_default list_scope NOT NULL DEFAULT 'either',
    created_by uuid,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE template_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    template_list_id uuid NOT NULL REFERENCES template_lists(id) ON DELETE CASCADE,
    title text NOT NULL,
    sort_order int NOT NULL,
    requires_signoff_default boolean,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE task_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    center_id uuid NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
    name text NOT NULL,
    description text,
    scope list_scope NOT NULL DEFAULT 'either',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE task_list_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_list_id uuid NOT NULL REFERENCES task_lists(id) ON DELETE CASCADE,
    title text NOT NULL,
    sort_order int NOT NULL,
    requires_signoff boolean,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE list_instances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    center_id uuid NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
    task_list_id uuid NOT NULL REFERENCES task_lists(id) ON DELETE CASCADE,
    room_id uuid REFERENCES rooms(id) ON DELETE SET NULL,
    name_override text,
    is_active boolean NOT NULL DEFAULT true,
    frequency frequency NOT NULL,
    interval int NOT NULL DEFAULT 1,
    byweekday text[],
    bymonthday int[],
    start_date date NOT NULL,
    end_date date,
    due_time time,
    requires_manager_signoff boolean NOT NULL DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE list_instance_managers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_instance_id uuid NOT NULL REFERENCES list_instances(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(list_instance_id, user_id)
);

CREATE TABLE list_instance_assignees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_instance_id uuid NOT NULL REFERENCES list_instances(id) ON DELETE CASCADE,
    assignee_type assignee_type NOT NULL,
    role membership_role,
    user_id uuid,
    room_id uuid REFERENCES rooms(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE task_overrides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_instance_id uuid NOT NULL REFERENCES list_instances(id) ON DELETE CASCADE,
    base_task_id uuid REFERENCES task_list_tasks(id) ON DELETE SET NULL,
    title_override text,
    is_disabled boolean NOT NULL DEFAULT false,
    sort_order_override int,
    frequency_override frequency,
    interval_override int,
    byweekday_override text[],
    bymonthday_override int[],
    due_time_override time,
    requires_signoff_override boolean,
    assigned_user_id uuid,
    assigned_role membership_role,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE task_completions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_instance_id uuid NOT NULL REFERENCES list_instances(id) ON DELETE CASCADE,
    task_ref_type task_ref_type NOT NULL,
    task_ref_id uuid NOT NULL,
    occurrence_date date NOT NULL,
    completed_by uuid NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now(),
    status completion_status NOT NULL DEFAULT 'completed',
    created_at timestamptz DEFAULT now(),
    UNIQUE(list_instance_id, task_ref_type, task_ref_id, occurrence_date)
);

CREATE TABLE list_signoffs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_instance_id uuid NOT NULL REFERENCES list_instances(id) ON DELETE CASCADE,
    occurrence_date date NOT NULL,
    signed_off_by uuid NOT NULL,
    signed_off_at timestamptz NOT NULL DEFAULT now(),
    notes text,
    created_at timestamptz DEFAULT now(),
    UNIQUE(list_instance_id, occurrence_date)
);

-- INDEXES

CREATE INDEX idx_centers_group_id ON centers(group_id);
CREATE INDEX idx_rooms_center_id ON rooms(center_id);
CREATE INDEX idx_center_memberships_user_id ON center_memberships(user_id);
CREATE INDEX idx_center_memberships_center_role ON center_memberships(center_id, role);
CREATE INDEX idx_center_memberships_center_status ON center_memberships(center_id, status);
CREATE INDEX idx_template_tasks_list_sort ON template_tasks(template_list_id, sort_order);
CREATE INDEX idx_task_lists_center_active ON task_lists(center_id, is_active);
CREATE INDEX idx_task_list_tasks_list_sort ON task_list_tasks(task_list_id, sort_order);
CREATE INDEX idx_list_instances_center_room ON list_instances(center_id, room_id);
CREATE INDEX idx_list_instances_center_active ON list_instances(center_id, is_active);
CREATE INDEX idx_list_instances_task_list ON list_instances(task_list_id);
CREATE INDEX idx_list_instances_center_frequency ON list_instances(center_id, frequency);
CREATE INDEX idx_list_instance_managers_user ON list_instance_managers(user_id);
CREATE INDEX idx_list_instance_managers_instance ON list_instance_managers(list_instance_id);
CREATE INDEX idx_list_instance_assignees_instance ON list_instance_assignees(list_instance_id);
CREATE INDEX idx_list_instance_assignees_type ON list_instance_assignees(assignee_type);
CREATE INDEX idx_task_overrides_instance ON task_overrides(list_instance_id);
CREATE INDEX idx_task_overrides_base_task ON task_overrides(base_task_id);
CREATE INDEX idx_task_completions_instance_date ON task_completions(list_instance_id, occurrence_date);
CREATE INDEX idx_task_completions_user_date ON task_completions(completed_by, occurrence_date);
CREATE INDEX idx_list_signoffs_instance_date ON list_signoffs(list_instance_id, occurrence_date);
CREATE INDEX idx_list_signoffs_user ON list_signoffs(signed_off_by);
