PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  user_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('citizen','collector','recycler','admin')),
  password_hash TEXT NOT NULL,
  reset_token TEXT,
  reset_expires_at TEXT,
  active_flag INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS collectors (
  collector_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL UNIQUE,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  vehicle TEXT,
  area TEXT,
  active_flag INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS recyclers (
  recycler_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL UNIQUE,
  company_name TEXT NOT NULL,
  location TEXT,
  contact_person TEXT,
  phone TEXT,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS pickup_requests (
  request_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  location TEXT NOT NULL,
  area TEXT,
  latitude REAL,
  longitude REAL,
  battery_type TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  remarks TEXT,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS assignments (
  assignment_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id INTEGER NOT NULL UNIQUE,
  collector_id INTEGER NOT NULL,
  assigned_at TEXT NOT NULL,
  assigned_by INTEGER,
  accepted_at TEXT,
  FOREIGN KEY (request_id) REFERENCES pickup_requests(request_id),
  FOREIGN KEY (collector_id) REFERENCES collectors(collector_id),
  FOREIGN KEY (assigned_by) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS custody_transfers (
  transfer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id INTEGER NOT NULL,
  collector_id INTEGER NOT NULL,
  recycler_id INTEGER NOT NULL,
  status TEXT NOT NULL,
  transfer_date TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (request_id) REFERENCES pickup_requests(request_id),
  FOREIGN KEY (collector_id) REFERENCES collectors(collector_id),
  FOREIGN KEY (recycler_id) REFERENCES recyclers(recycler_id)
);

CREATE TABLE IF NOT EXISTS status_history (
  history_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id INTEGER NOT NULL,
  old_status TEXT,
  new_status TEXT NOT NULL,
  updated_by INTEGER,
  updated_time TEXT NOT NULL,
  note TEXT,
  FOREIGN KEY (request_id) REFERENCES pickup_requests(request_id),
  FOREIGN KEY (updated_by) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS notifications (
  notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient TEXT NOT NULL,
  user_id INTEGER,
  channel TEXT NOT NULL,
  status TEXT NOT NULL,
  message TEXT NOT NULL,
  provider TEXT,
  provider_message_id TEXT,
  delivery_status TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_logs (
  log_id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  actor INTEGER,
  entity TEXT,
  entity_id TEXT,
  detail TEXT,
  timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS uploads (
  upload_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  file_path TEXT NOT NULL,
  mime_type TEXT,
  uploader INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY (request_id) REFERENCES pickup_requests(request_id),
  FOREIGN KEY (uploader) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS notification_queue (
  queue_id INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id INTEGER NOT NULL,
  payload TEXT NOT NULL,
  next_attempt_at TEXT NOT NULL,
  done INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (notification_id) REFERENCES notifications(notification_id)
);

CREATE TABLE IF NOT EXISTS mpesa_sandbox_tx (
  tx_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id INTEGER,
  amount REAL,
  phone TEXT,
  status TEXT NOT NULL,
  checkout_id TEXT,
  result TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  hits INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pickup_status ON pickup_requests(status);
CREATE INDEX IF NOT EXISTS idx_pickup_user ON pickup_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_history_request ON status_history(request_id);
CREATE INDEX IF NOT EXISTS idx_notif_recipient ON notifications(recipient);
