const { Pool } = require('pg');
const fs = require('fs');

const pool = new Pool({
  connectionString: process.env.NEON_PG_URI || 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

async function migrate() {
  try {
    console.log('Running schema migration...');
    
    const schema = fs.readFileSync('./schema.sql', 'utf8');
    await pool.query(schema);
    
    console.log('✅ Schema migration complete');
    
    // Verify tables exist
    const tables = await pool.query(`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public'
      ORDER BY table_name
    `);
    
    console.log('\nTables in database:');
    tables.rows.forEach(row => console.log(`  - ${row.table_name}`));
    
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

migrate();
